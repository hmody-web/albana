import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/map_launcher_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import '../widgets/shared_widgets.dart';

class CoursesPage extends StatefulWidget {
  final bool isDark;
  const CoursesPage({super.key, required this.isDark});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage>
    with SingleTickerProviderStateMixin {
  static const gold = Color(0xFFD4A017);

  late TabController _tabController;

  static const _apiKey = 'AIzaSyDwiUw3uEO5xqafhsfMZ0KVFYUhQ9hvmh8';
  static const _channelId = 'UCkIanvr92e8SPMgZo5y5P7g';
  static const _scheduleUrl =
      'https://majidalbana.com/admin/table/load_schedule.php';
  static const _addScheduleUrl =
      'https://majidalbana.com/admin/table/add_schedule.php';
  static const _deleteScheduleUrl =
      'https://majidalbana.com/admin/table/delete_schedule.php';
  static const _updateScheduleUrl =
      'https://majidalbana.com/admin/table/update_schedule.php';
  static const _reorderScheduleUrl =
      'https://majidalbana.com/admin/table/reorder_schedule.php';
  static const _scheduleCacheKey = 'schedule_cache_v1';

  List<Map<String, String>> _videos = [];
  bool _loadingVideos = true;
  String? _videoError;

  List<_ScheduleItem> _schedule = [];
  bool _loadingSchedule = true;
  String? _scheduleError;

  Timer? _pollTimer;
  String _lastScheduleHash = '';

  bool _isSupervisor(User? user) {
    final email = user?.email?.trim().toLowerCase();
    return email == 'hmode.qq@gmail.com' || email == 'hmode.qu@gmail.com';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchVideos();
    _fetchSchedule();
    // بدء المراقبة الخفية كل 8 ثواني
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _silentPollSchedule();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchVideos() async {
    setState(() {
      _loadingVideos = true;
      _videoError = null;
    });

    try {
      final searchUri = Uri.https('www.googleapis.com', '/youtube/v3/search', {
        'part': 'snippet',
        'channelId': _channelId,
        'order': 'date',
        'maxResults': '20',
        'type': 'video',
        'key': _apiKey,
      });

      final response = await http.get(searchUri);
      if (response.statusCode != 200) {
        throw Exception('فشل الاتصال: HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>;

      final videos = items.map<Map<String, String>>((item) {
        final snippet = item['snippet'] as Map<String, dynamic>;
        final videoId =
            (item['id'] as Map<String, dynamic>)['videoId'] as String;
        final title = snippet['title'] as String;
        final publishedAt =
            (snippet['publishedAt'] as String).substring(0, 10);
        final thumbs = snippet['thumbnails'] as Map<String, dynamic>;
        final thumb =
            ((thumbs['medium'] ?? thumbs['default']) as Map<String, dynamic>)[
                'url'] as String;

        return {
          'id': videoId,
          'title': title,
          'thumb': thumb,
          'date': publishedAt,
        };
      }).toList();

      setState(() {
        _videos = videos;
        _loadingVideos = false;
      });
    } catch (e) {
if (mounted) {
  setState(() {
    _videoError = e.toString();
    _loadingVideos = false;
  });
}
    }
  }

  Future<void> _fetchSchedule() async {
    // ── 1. اقرأ الكاش أولاً وأظهره فوراً ──
    final cached = await _loadScheduleFromCache();
    if (cached.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _schedule = cached;
        _loadingSchedule = false;
        _lastScheduleHash = _computeHash(cached);
      });
      // ── 2. جلب التحديثات من الخادم في الخلفية ──
      _silentPollSchedule();
      return;
    }

    // ── لا يوجد كاش: تحميل أول مرة مع مؤشر التحميل ──
    setState(() {
      _loadingSchedule = true;
      _scheduleError = null;
    });

    try {
      final items = await _loadScheduleItems();
      if (!mounted) return;
      final hash = _computeHash(items);
      await _saveScheduleToCache(items);
      setState(() {
        _schedule = items;
        _loadingSchedule = false;
        _lastScheduleHash = hash;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scheduleError = e.toString();
        _loadingSchedule = false;
      });
    }
  }

  // ── Cache Helpers ──────────────────────────────────────────────────────────

  /// تحويل قائمة العناصر إلى JSON لحفظها
  List<Map<String, dynamic>> _itemsToJson(List<_ScheduleItem> items) {
    return items.map((e) => {
      'id': e.id,
      'lectureNumber': e.lectureNumber,
      'day': e.day,
      'time': e.time,
      'location': e.location,
      'urlLocation': e.urlLocation,
    }).toList();
  }

  /// قراءة الجدول من الكاش المحلي
  Future<List<_ScheduleItem>> _loadScheduleFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_scheduleCacheKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => _ScheduleItem(
        id: e['id'] as String? ?? '',
        lectureNumber: e['lectureNumber'] as String? ?? '',
        day: e['day'] as String? ?? '',
        time: e['time'] as String? ?? '',
        location: e['location'] as String? ?? '',
        urlLocation: e['urlLocation'] as String? ?? '',
      )).toList();
    } catch (_) {
      return [];
    }
  }

  /// حفظ الجدول في الكاش المحلي
  Future<void> _saveScheduleToCache(List<_ScheduleItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_scheduleCacheKey, jsonEncode(_itemsToJson(items)));
    } catch (_) {}
  }

  /// تحميل عناصر الجدول من الخادم (مشترك)
  Future<List<_ScheduleItem>> _loadScheduleItems() async {
    final response = await http.get(Uri.parse(_scheduleUrl));
    if (response.statusCode != 200) {
      throw Exception('فشل الاتصال: HTTP ${response.statusCode}');
    }

    final html = utf8.decode(response.bodyBytes);
    final rows = RegExp(r'<tr[^>]*>(.*?)</tr>',
            dotAll: true, caseSensitive: false)
        .allMatches(html);

    final items = <_ScheduleItem>[];
    for (final row in rows) {
      final rowHtml = row.group(1) ?? '';
      final cells =
          RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true, caseSensitive: false)
              .allMatches(rowHtml)
              .map((m) => m.group(1) ?? '')
              .toList();

      if (cells.length < 4) continue;

      final locationHtml = cells[3];
final urlMatch =
    RegExp(r'''href=["']([^"']+)["']''', caseSensitive: false)
        .firstMatch(locationHtml);

      final idMatch =
          RegExp(r'''data-id=[\"\''](\d+)[\"\'']''', caseSensitive: false)
              .firstMatch(rowHtml);

      items.add(_ScheduleItem(
        id: idMatch?.group(1) ?? '',
        lectureNumber: _cleanHtml(cells[0]),
        day: _cleanHtml(cells[1]),
        time: _cleanHtml(cells[2]),
        location: _cleanHtml(
          locationHtml.replaceAll(
            RegExp(r'<a\b[^>]*>.*?</a>',
                dotAll: true, caseSensitive: false),
            '',
          ),
        ),
        urlLocation: urlMatch?.group(1)?.trim() ?? '',
      ));
    }

    // الخادم يُرجع البيانات مرتبة بـ sort_order، لا نعيد ترتيبها هنا
    return items;
  }

  /// حساب hash بسيط للكشف عن التغييرات
  String _computeHash(List<_ScheduleItem> items) {
    return items.map((e) => '${e.id}|${e.lectureNumber}|${e.day}|${e.time}|${e.location}').join(';');
  }

  /// مراقبة خفية كل 8 ثواني — لا تُظهر أي loading indicator
  Future<void> _silentPollSchedule() async {
    if (!mounted) return;
    try {
      final items = await _loadScheduleItems();
      if (!mounted) return;
      final hash = _computeHash(items);
      if (hash != _lastScheduleHash) {
        await _saveScheduleToCache(items);
        if (!mounted) return;
        setState(() {
          _schedule = items;
          _lastScheduleHash = hash;
        });
      }
    } catch (_) {
      // فشل صامت — لا نُظهر خطأ للمستخدم
    }
  }

  Future<void> _addSchedule(_ScheduleItem item) async {
    // ── تحديث فوري في الواجهة قبل انتظار الخادم ──
    final tempItem = item.copyWith(id: 'temp_${DateTime.now().millisecondsSinceEpoch}');
    setState(() {
      _schedule.insert(0, tempItem);
    });

    try {
      final response = await http.post(
        Uri.parse(_addScheduleUrl),
        body: {
          'lecture_number': item.lectureNumber,
          'day': item.day,
          'time': item.time,
          'location': item.location,
          'url_location': item.urlLocation,
        },
      );
      if (response.statusCode == 200) {
        final items = await _loadScheduleItems();
        if (!mounted) return;
        await _saveScheduleToCache(items);
        setState(() {
          _schedule = items;
          _lastScheduleHash = _computeHash(items);
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _schedule.removeWhere((e) => e.id == tempItem.id);
      });
    }
  }

  Future<void> _deleteSchedule(String id) async {
    // ── إزالة فورية من الواجهة ──
    final backup = List<_ScheduleItem>.from(_schedule);
    setState(() {
      _schedule.removeWhere((e) => e.id == id);
    });

    try {
      await http.post(
        Uri.parse(_deleteScheduleUrl),
        body: {'id': id},
      );
      if (mounted) {
        _lastScheduleHash = _computeHash(_schedule);
        await _saveScheduleToCache(_schedule);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _schedule = backup);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white70 : Colors.black54;
    final cardBg = isDark ? const Color(0xFF181818) : Colors.white;
    final bg = isDark ? const Color(0xFF111111) : const Color(0xFFF7F3EC);

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final isAdmin = _isSupervisor(user);

        return CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const BouncingScrollPhysics(),
          slivers: [
            PremiumAppBar(title: 'الدورات والمحاضرات', isDark: isDark),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                tabController: _tabController,
                isDark: isDark,
                bg: bg,
              ),
            ),
            SliverFillRemaining(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _CoursesTab(
                    isDark: isDark,
                    textPrimary: textPrimary,
                    textSub: textSub,
                    cardBg: cardBg,
                    schedule: _schedule,
                    loadingSchedule: _loadingSchedule,
                    scheduleError: _scheduleError,
                    onRetrySchedule: _fetchSchedule,
                    isAdmin: isAdmin,
                    onAddSchedule: _addSchedule,
                    onDeleteSchedule: _deleteSchedule,
                    onReorderSchedule: (oldIndex, newIndex) async {
                      // ── تحريك الصف في الواجهة فوراً ──
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = _schedule.removeAt(oldIndex);
                        _schedule.insert(newIndex, item);
                      });
                      await _saveScheduleToCache(_schedule);
                      _lastScheduleHash = _computeHash(_schedule);
                      // إرسال الترتيب الجديد للخادم
                      try {
                        final order = _schedule.map((e) => e.id).toList();
                        await http.post(
                          Uri.parse(_reorderScheduleUrl),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'order': order}),
                        );
                      } catch (_) {
                        // فشل صامت - الترتيب محفوظ في الكاش المحلي
                      }
                    },
                    onEditSchedule: (oldItem, newItem) async {
                      // ── تعديل فوري في الواجهة بنفس الـ id تماماً ──
                      final idx = _schedule.indexWhere((e) => e.id == oldItem.id);
                      if (idx != -1) {
                        setState(() {
                          _schedule[idx] = newItem.copyWith(id: oldItem.id);
                        });
                        await _saveScheduleToCache(_schedule);
                      }
                      // إرسال UPDATE حقيقي للخادم بنفس الـ id
                      try {
                        final response = await http.post(
                          Uri.parse(_updateScheduleUrl),
                          body: {
                            'id': oldItem.id,
                            'lecture_number': newItem.lectureNumber,
                            'day': newItem.day,
                            'time': newItem.time,
                            'location': newItem.location,
                            'url_location': newItem.urlLocation,
                          },
                        );
                        if (response.statusCode == 200 && mounted) {
                          _lastScheduleHash = _computeHash(_schedule);
                        } else if (mounted) {
                          await _fetchSchedule();
                        }
                      } catch (_) {
                        if (mounted) await _fetchSchedule();
                      }
                    },
                  ),
                  _LecturesTab(
                    isDark: isDark,
                    textPrimary: textPrimary,
                    textSub: textSub,
                    cardBg: cardBg,
                    videos: _videos,
                    loading: _loadingVideos,
                    error: _videoError,
                    onRetry: _fetchVideos,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Schedule Item Model (with id)
// ─────────────────────────────────────────────────────────────────────────────
class _ScheduleItem {
  final String id;
  final String lectureNumber;
  final String day;
  final String time;
  final String location;
  final String urlLocation;

  const _ScheduleItem({
    this.id = '',
    required this.lectureNumber,
    required this.day,
    required this.time,
    required this.location,
    required this.urlLocation,
  });

  _ScheduleItem copyWith({
    String? id,
    String? lectureNumber,
    String? day,
    String? time,
    String? location,
    String? urlLocation,
  }) {
    return _ScheduleItem(
      id: id ?? this.id,
      lectureNumber: lectureNumber ?? this.lectureNumber,
      day: day ?? this.day,
      time: time ?? this.time,
      location: location ?? this.location,
      urlLocation: urlLocation ?? this.urlLocation,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────
String _cleanHtml(String value) {
  var text = value
      .replaceAll(RegExp(r'<[^>]*>', dotAll: true), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

int _parseLectureNumber(String value) {
  const arabic = {
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9'
  };
  var normalized = value;
  arabic.forEach((k, v) => normalized = normalized.replaceAll(k, v));
  return int.tryParse(normalized.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Bar Delegate
// ─────────────────────────────────────────────────────────────────────────────
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabController tabController;
  final bool isDark;
  final Color bg;

  const _TabBarDelegate({
    required this.tabController,
    required this.isDark,
    required this.bg,
  });

  static const gold = Color(0xFFD4A017);

  @override
  double get minExtent => 56;
  @override
  double get maxExtent => 56;

  @override
  Widget build(BuildContext ctx, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF222222) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: gold.withOpacity(0.2)),
        ),
        child: TabBar(
          controller: tabController,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [Color(0xFFD4A017), Color(0xFFFFCC44)],
            ),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: Colors.black,
          unselectedLabelColor: isDark ? Colors.white54 : Colors.black45,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'الدورات التدريبية'),
            Tab(text: 'المحاضرات'),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate old) =>
      old.isDark != isDark || old.tabController != tabController;
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1 – COURSES
// ─────────────────────────────────────────────────────────────────────────────
class _CoursesTab extends StatelessWidget {
  final bool isDark;
  final Color textPrimary, textSub, cardBg;
  final List<_ScheduleItem> schedule;
  final bool loadingSchedule;
  final String? scheduleError;
  final VoidCallback onRetrySchedule;
  final bool isAdmin;
  final Future<void> Function(_ScheduleItem) onAddSchedule;
  final Future<void> Function(String) onDeleteSchedule;
  final Future<void> Function(int, int) onReorderSchedule;
  final Future<void> Function(_ScheduleItem, _ScheduleItem) onEditSchedule;

  const _CoursesTab({
    required this.isDark,
    required this.textPrimary,
    required this.textSub,
    required this.cardBg,
    required this.schedule,
    required this.loadingSchedule,
    required this.scheduleError,
    required this.onRetrySchedule,
    required this.isAdmin,
    required this.onAddSchedule,
    required this.onDeleteSchedule,
    required this.onReorderSchedule,
    required this.onEditSchedule,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      children: [
        // ── Course Card ──────────────────────────────────────────────────────
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF111111)
                  : const Color(0xFF1A1200),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: gold.withOpacity(0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.asset(
                        'assets/images/dora.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 210,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF2A1C00), Color(0xFF1A1200)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.72),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 14,
                      right: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(209, 206, 204, 201),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: const Text(
                          'دورة احترافية',
                          style: TextStyle(
                            color: Color(0xFF1A0F00),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      right: 16,
                      left: 16,
                      child: const Text(
                        'دورة تدريبية لتنمية مهندس موقع',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          height: 1.45,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 8)
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'دورة علمية متكاملة تهدف إلى تمكين الطلبة والمهندسين من إدارة المواقع الإنشائية باحترافية عالية وتطوير مهاراتهم التقنية.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.62),
                          fontSize: 12.5,
                          height: 1.8,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipBadge(
                            icon: Icons.access_time_rounded,
                            label: schedule.isNotEmpty
                                ? '+${schedule.length} محاضرة'
                                : '+25 محاضرة',
                          ),
                          const _ChipBadge(
                              icon: Icons.people_rounded, label: ' للخريجين'),
                          const _ChipBadge(
                              icon: Icons.verified_rounded, label: 'شهادة '),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),

        // ── Schedule Table Header ────────────────────────────────────────────
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: gold,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'جدول المحاضرات',
              style: TextStyle(
                color: textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // ── Admin Add Box ────────────────────────────────────────────────────
        if (isAdmin)
          _AdminAddBox(
            isDark: isDark,
            cardBg: cardBg,
            textPrimary: textPrimary,
            textSub: textSub,
            onAdd: onAddSchedule,
          ),

        if (isAdmin) const SizedBox(height: 14),

        // ── Table ───────────────────────────────────────────────────────────
        _ScheduleTable(
          schedule: schedule,
          loading: loadingSchedule,
          error: scheduleError,
          onRetry: onRetrySchedule,
          isDark: isDark,
          textPrimary: textPrimary,
          textSub: textSub,
          cardBg: cardBg,
          isAdmin: isAdmin,
          onDelete: onDeleteSchedule,
          onEdit: onEditSchedule,
          onReorder: onReorderSchedule,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Add Box
// ─────────────────────────────────────────────────────────────────────────────
class _AdminAddBox extends StatefulWidget {
  final bool isDark;
  final Color cardBg, textPrimary, textSub;
  final Future<void> Function(_ScheduleItem) onAdd;

  const _AdminAddBox({
    required this.isDark,
    required this.cardBg,
    required this.textPrimary,
    required this.textSub,
    required this.onAdd,
  });

  @override
  State<_AdminAddBox> createState() => _AdminAddBoxState();
}

class _AdminAddBoxState extends State<_AdminAddBox>
    with SingleTickerProviderStateMixin {
  static const gold = Color(0xFFD4A017);

  bool _expanded = false;
  bool _loading = false;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  final _numCtrl = TextEditingController();
  final _dayCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();
  final _locCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _numCtrl.dispose();
    _dayCtrl.dispose();
    _timeCtrl.dispose();
    _locCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animCtrl.forward();
    } else {
      _animCtrl.reverse();
    }
  }

  Future<void> _submit() async {
    if (_numCtrl.text.isEmpty ||
        _dayCtrl.text.isEmpty ||
        _timeCtrl.text.isEmpty ||
        _locCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى ملء جميع الحقول المطلوبة'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    await widget.onAdd(_ScheduleItem(
      lectureNumber: _numCtrl.text.trim(),
      day: _dayCtrl.text.trim(),
      time: _timeCtrl.text.trim(),
      location: _locCtrl.text.trim(),
      urlLocation: _urlCtrl.text.trim(),
    ));

    _numCtrl.clear();
    _dayCtrl.clear();
    _timeCtrl.clear();
    _locCtrl.clear();
    _urlCtrl.clear();

    setState(() {
      _loading = false;
      _expanded = false;
    });
    _animCtrl.reverse();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('تمت إضافة المحاضرة بنجاح'),
          ],
        ),
        backgroundColor: const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1500) : const Color(0xFFFFFBF0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: gold.withOpacity(_expanded ? 0.5 : 0.25),
          width: _expanded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: gold.withOpacity(_expanded ? 0.12 : 0.05),
            blurRadius: _expanded ? 20 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header / Toggle ───────────────────────────────────────────────
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD86B), Color(0xFFD4A017)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: gold.withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add_rounded,
                        color: Colors.black, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إضافة محاضرة جديدة',
                          style: TextStyle(
                            color: widget.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'خاص بالمشرف',
                          style: TextStyle(
                            color: gold.withOpacity(0.7),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: gold,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Form ─────────────────────────────────────────────────────────
          SizeTransition(
            sizeFactor: _fadeAnim,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  Divider(color: gold.withOpacity(0.15), height: 1),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _AdminField(
                          controller: _numCtrl,
                          label: 'رقم المحاضرة',
                          icon: Icons.tag_rounded,
                          isDark: isDark,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _AdminField(
                          controller: _dayCtrl,
                          label: 'اليوم / التاريخ',
                          icon: Icons.calendar_today_rounded,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _AdminField(
                          controller: _timeCtrl,
                          label: 'الوقت',
                          icon: Icons.access_time_rounded,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _AdminField(
                          controller: _locCtrl,
                          label: 'الموقع',
                          icon: Icons.location_on_rounded,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _AdminField(
                          controller: _urlCtrl,
                          label: 'رابط الموقع (اختياري)',
                          icon: Icons.link_rounded,
                          isDark: isDark,
                          keyboardType: TextInputType.url,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () async {
                          final raw = _urlCtrl.text.trim();
                          if (raw.isEmpty) return;
                          var url = raw;
                          if (!url.startsWith('http://') && !url.startsWith('https://')) {
                            url = 'https://$url';
                          }
                          final uri = Uri.tryParse(url);
                          if (uri != null && await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD86B), Color(0xFFD4A017)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: gold.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: Colors.black,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFD86B), Color(0xFFD4A017)],
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.black,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.send_rounded,
                                        color: Colors.black, size: 17),
                                    SizedBox(width: 8),
                                    Text(
                                      'نشر المحاضرة',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Text Field
// ─────────────────────────────────────────────────────────────────────────────
class _AdminField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isDark;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _AdminField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.isDark,
    this.keyboardType,
    this.inputFormatters,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textAlign: TextAlign.right,
      style: TextStyle(
        color: isDark ? Colors.white : const Color(0xFF1A1000),
        fontSize: 13,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: gold.withOpacity(0.7),
          fontSize: 12,
        ),
        prefixIcon: Icon(icon, color: gold, size: 18),
        filled: true,
        fillColor:
            isDark ? Colors.white.withOpacity(0.06) : gold.withOpacity(0.06),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: gold.withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: gold.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: gold, width: 1.5),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Schedule Table
// ─────────────────────────────────────────────────────────────────────────────
class _ScheduleTable extends StatelessWidget {
  final List<_ScheduleItem> schedule;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final bool isDark;
  final Color textPrimary, textSub, cardBg;
  final bool isAdmin;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(_ScheduleItem, _ScheduleItem) onEdit;
  final Future<void> Function(int, int) onReorder;

  const _ScheduleTable({
    required this.schedule,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.isDark,
    required this.textPrimary,
    required this.textSub,
    required this.cardBg,
    required this.isAdmin,
    required this.onDelete,
    required this.onEdit,
    required this.onReorder,
  });

  static const gold = Color(0xFFD4A017);

  void _openLocation(BuildContext context, String rawUrl) {
    MapLauncherService.openMapPicker(
      context: context,
      rawUrl: rawUrl,
      isDark: isDark,
    );
  }

  void _showEditDialog(BuildContext context, _ScheduleItem item, int index) {
    final numCtrl = TextEditingController(text: item.lectureNumber);
    final dayCtrl = TextEditingController(text: item.day);
    final timeCtrl = TextEditingController(text: item.time);
    final locCtrl = TextEditingController(text: item.location);
    final urlCtrl = TextEditingController(text: item.urlLocation);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditBottomSheet(
        isDark: isDark,
        item: item,
        numCtrl: numCtrl,
        dayCtrl: dayCtrl,
        timeCtrl: timeCtrl,
        locCtrl: locCtrl,
        urlCtrl: urlCtrl,
        onSave: (newItem) async {
          await onEdit(item, newItem);
        },
        onDelete: () async {
          if (item.id.isNotEmpty) {
            await onDelete(item.id);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: _boxDecoration(),
        child: Column(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(color: gold, strokeWidth: 2.5),
            ),
            const SizedBox(height: 12),
            Text('جارٍ تحميل جدول المحاضرات...',
                style: TextStyle(color: textSub, fontSize: 12.5)),
          ],
        ),
      );
    }

    if (error != null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: _boxDecoration(),
        child: Column(
          children: [
            const Icon(Icons.wifi_off_rounded, color: gold, size: 34),
            const SizedBox(height: 8),
            Text('تعذّر جلب جدول المحاضرات',
                style: TextStyle(
                    color: textPrimary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('إعادة المحاولة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    if (schedule.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: _boxDecoration(),
        child: Text('لا توجد محاضرات حالياً',
            textAlign: TextAlign.center,
            style: TextStyle(color: textSub)),
      );
    }

    return Container(
      decoration: _boxDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header Row
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFFD4A017), Color(0xFFB8860B)]),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            child: Row(
              children: [
                const _HeaderCell(text: '#', flex: 1),
                const _HeaderCell(text: 'اليوم', flex: 2),
                const _HeaderCell(text: 'الوقت', flex: 2),
                const _HeaderCell(text: 'الموقع', flex: 3),
                if (isAdmin) const SizedBox(width: 32),
                if (isAdmin) const SizedBox(width: 24),
              ],
            ),
          ),
          // Data Rows — reorderable for admin, normal for users
          if (isAdmin)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: schedule.length,
              onReorder: (oldIndex, newIndex) => onReorder(oldIndex, newIndex),
              proxyDecorator: (child, index, animation) => Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                shadowColor: gold.withOpacity(0.4),
                child: child,
              ),
              itemBuilder: (ctx, i) {
                final row = schedule[i];
                final isEven = i % 2 == 0;
                return _buildRow(ctx, i, row, isEven);
              },
            )
          else
            ...schedule.asMap().entries.map((entry) {
              return _buildRow(context, entry.key, entry.value, entry.key % 2 == 0);
            }),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, int i, _ScheduleItem row, bool isEven) {
    return Container(
      key: ValueKey(row.id),
      color: isEven
          ? (isDark
              ? Colors.white.withOpacity(0.03)
              : const Color(0xFFFFF9EE))
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(
        children: [
          // Drag handle for admin
          if (isAdmin)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.drag_handle_rounded,
                  color: gold.withOpacity(0.45), size: 18),
            ),
          // Lecture Number
          Expanded(
            flex: 1,
            child: Center(
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: gold.withOpacity(0.15),
                  border: Border.all(color: gold.withOpacity(0.22)),
                ),
                alignment: Alignment.center,
                child: Text(
                  row.lectureNumber,
                  style: const TextStyle(
                      color: gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
          _DataCell(text: row.day, flex: 2, color: textPrimary),
          _DataCell(text: row.time, flex: 2, color: textSub),
          // Location cell
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                if (row.urlLocation.isNotEmpty)
                  Flexible(
                    child: Text(
                      row.location,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: textPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600),
                    ),
                  )
                else
                  Expanded(
                    child: Text(
                      row.location,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: textPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                if (row.urlLocation.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  GestureDetector(
                    onTap: () => _openLocation(context, row.urlLocation),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD86B), Color(0xFFD4A017)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: gold.withOpacity(0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: Colors.black,
                        size: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Admin Edit Button
          if (isAdmin)
            GestureDetector(
              onTap: () => _showEditDialog(context, row, i),
              child: Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: gold.withOpacity(0.12),
                  border: Border.all(
                      color: gold.withOpacity(0.3), width: 1),
                ),
                child: const Icon(Icons.edit_rounded,
                    color: gold, size: 13),
              ),
            ),
        ],
      ),
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: gold.withOpacity(0.15)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _EditBottomSheet extends StatefulWidget {
  final bool isDark;
  final _ScheduleItem item;
  final TextEditingController numCtrl, dayCtrl, timeCtrl, locCtrl, urlCtrl;
  final Future<void> Function(_ScheduleItem) onSave;
  final Future<void> Function() onDelete;

  const _EditBottomSheet({
    required this.isDark,
    required this.item,
    required this.numCtrl,
    required this.dayCtrl,
    required this.timeCtrl,
    required this.locCtrl,
    required this.urlCtrl,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<_EditBottomSheet> createState() => _EditBottomSheetState();
}

class _EditBottomSheetState extends State<_EditBottomSheet> {
  static const gold = Color(0xFFD4A017);
  bool _saving = false;
  bool _deleting = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final newItem = widget.item.copyWith(
      lectureNumber: widget.numCtrl.text.trim(),
      day: widget.dayCtrl.text.trim(),
      time: widget.timeCtrl.text.trim(),
      location: widget.locCtrl.text.trim(),
      urlLocation: widget.urlCtrl.text.trim(),
    );
    await widget.onSave(newItem);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor:
            widget.isDark ? const Color(0xFF1A1A1A) : Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('حذف المحاضرة',
            style: TextStyle(
                color: widget.isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.w800)),
        content: Text(
            'هل أنت متأكد من حذف المحاضرة رقم ${widget.item.lectureNumber}؟',
            style: TextStyle(
                color: widget.isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('إلغاء',
                style: TextStyle(
                    color: widget.isDark ? Colors.white54 : Colors.black45)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('حذف',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _deleting = true);
      await widget.onDelete();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? const Color(0xFF1C1600) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: gold.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.5 : 0.15),
            blurRadius: 30,
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: gold.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 18),

                // Title
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD86B), Color(0xFFD4A017)],
                        ),
                      ),
                      child: const Icon(Icons.edit_rounded,
                          color: Colors.black, size: 17),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'تعديل المحاضرة',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    Expanded(
                      child: _AdminField(
                        controller: widget.numCtrl,
                        label: 'رقم المحاضرة',
                        icon: Icons.tag_rounded,
                        isDark: isDark,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AdminField(
                        controller: widget.dayCtrl,
                        label: 'اليوم / التاريخ',
                        icon: Icons.calendar_today_rounded,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _AdminField(
                        controller: widget.timeCtrl,
                        label: 'الوقت',
                        icon: Icons.access_time_rounded,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AdminField(
                        controller: widget.locCtrl,
                        label: 'الموقع',
                        icon: Icons.location_on_rounded,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // رابط الموقع مع زر فتح مباشر
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _AdminField(
                        controller: widget.urlCtrl,
                        label: 'رابط الموقع (اختياري)',
                        icon: Icons.link_rounded,
                        isDark: isDark,
                        keyboardType: TextInputType.url,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // زر فتح الرابط للتحقق منه
                    StatefulBuilder(
                      builder: (ctx, setLocal) {
                        return GestureDetector(
                          onTap: () async {
                            final raw = widget.urlCtrl.text.trim();
                            if (raw.isEmpty) return;
                            var url = raw;
                            if (!url.startsWith('http://') && !url.startsWith('https://')) {
                              url = 'https://$url';
                            }
                            final uri = Uri.tryParse(url);
                            if (uri != null && await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFD86B), Color(0xFFD4A017)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: gold.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: Colors.black,
                              size: 20,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Action Buttons
                Row(
                  children: [
                    // Delete
                    Expanded(
                      flex: 1,
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed:
                              _deleting || _saving ? null : _confirmDelete,
                          icon: _deleting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.redAccent),
                                )
                              : const Icon(Icons.delete_outline_rounded,
                                  size: 16, color: Colors.redAccent),
                          label: const Text('حذف',
                              style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: Colors.redAccent.withOpacity(0.4)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Save
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _saving || _deleting ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFFFD86B),
                                  Color(0xFFD4A017)
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Container(
                              alignment: Alignment.center,
                              child: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.black),
                                    )
                                  : const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.check_rounded,
                                            color: Colors.black, size: 17),
                                        SizedBox(width: 6),
                                        Text(
                                          'حفظ التعديلات',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// TAB 2 – LECTURES (YouTube Videos)
// ─────────────────────────────────────────────────────────────────────────────
class _LecturesTab extends StatelessWidget {
  final bool isDark;
  final Color textPrimary, textSub, cardBg;
  final List<Map<String, String>> videos;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  const _LecturesTab({
    required this.isDark,
    required this.textPrimary,
    required this.textSub,
    required this.cardBg,
    required this.videos,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: gold),
            const SizedBox(height: 14),
            Text('جارٍ تحميل المحاضرات...',
                style: TextStyle(color: textSub, fontSize: 13)),
          ],
        ),
      );
    }

    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: gold, size: 48),
            const SizedBox(height: 12),
            Text('تعذّر تحميل المحاضرات',
                style: TextStyle(
                    color: textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('إعادة المحاولة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      children: [
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: gold.withOpacity(0.15)),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFFF0000), Color(0xFFCC0000)],
                  ),
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('م. ماجد البنا',
                        style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 15)),
                    const SizedBox(height: 4),
                    Text('قناة متخصصة في الهندسة الإنشائية والمدنية',
                        style: TextStyle(color: textSub, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF0000).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.subscriptions_rounded,
                        color: Color(0xFFFF0000), size: 14),
                    SizedBox(width: 4),
                    Text('YouTube',
                        style: TextStyle(
                            color: Color(0xFFFF0000),
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: gold,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'أحدث المحاضرات',
              style: TextStyle(
                color: textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${videos.length}',
                style: const TextStyle(
                    color: gold, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...videos.map((v) => _VideoCard(
              video: v,
              isDark: isDark,
              textPrimary: textPrimary,
              textSub: textSub,
              cardBg: cardBg,
            )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video Card
// ─────────────────────────────────────────────────────────────────────────────
class _VideoCard extends StatelessWidget {
  final Map<String, String> video;
  final bool isDark;
  final Color textPrimary, textSub, cardBg;

  const _VideoCard({
    required this.video,
    required this.isDark,
    required this.textPrimary,
    required this.textSub,
    required this.cardBg,
  });

  static const gold = Color(0xFFD4A017);

  Future<void> _openVideo() async {
    final videoId = video['id']!;
    final url = Uri.parse('https://www.youtube.com/watch?v=$videoId');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openVideo,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: gold.withOpacity(0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      video['thumb']!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: isDark
                            ? const Color(0xFF222222)
                            : const Color(0xFFEEEEEE),
                        child: const Icon(Icons.broken_image_rounded,
                            color: Colors.grey),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFFF0000).withOpacity(0.9),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('YouTube',
                          style: TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video['title']!,
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.calendar_today_rounded,
                                  size: 12, color: textSub),
                              const SizedBox(width: 4),
                              Text(
                                video['date']!,
                                style: TextStyle(color: textSub, fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFF0000).withOpacity(0.1),
                      ),
                      child: const Icon(Icons.open_in_new_rounded,
                          color: Color(0xFFFF0000), size: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Small Widgets
// ─────────────────────────────────────────────────────────────────────────────
class _ChipBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ChipBadge({required this.icon, required this.label});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: gold.withOpacity(0.1),
        border: Border.all(color: gold.withOpacity(0.22)),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: gold, size: 13),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: gold, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final int flex;
  const _HeaderCell({required this.text, required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  final int flex;
  final Color color;
  const _DataCell(
      {required this.text, required this.flex, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }
}