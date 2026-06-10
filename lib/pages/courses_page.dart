import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
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

  // ─── YouTube Data API v3 ──────────────────────────────────────────────────
  // Replace with your own API key
  static const _apiKey = 'AIzaSyDwiUw3uEO5xqafhsfMZ0KVFYUhQ9hvmh8';
  static const _channelId = 'UCkIanvr92e8SPMgZo5y5P7g'; // majidalbana3 channel ID
  static const _scheduleUrl = 'https://majidalbana.com/admin/table/load_schedule.php';

  List<Map<String, String>> _videos = [];
  bool _loadingVideos = true;
  String? _videoError;

  List<_ScheduleItem> _schedule = [];
  bool _loadingSchedule = true;
  String? _scheduleError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchVideos();
    _fetchSchedule();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchVideos() async {
    setState(() {
      _loadingVideos = true;
      _videoError = null;
    });

    try {
      // ── جلب الفيديوهات من قناة YouTube عبر Data API v3 ──
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
        final videoId = (item['id'] as Map<String, dynamic>)['videoId'] as String;
        final title = snippet['title'] as String;
        final publishedAt = (snippet['publishedAt'] as String).substring(0, 10);
        final thumbs = snippet['thumbnails'] as Map<String, dynamic>;
        final thumb = ((thumbs['medium'] ?? thumbs['default']) as Map<String, dynamic>)['url'] as String;

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
      setState(() {
        _videoError = e.toString();
        _loadingVideos = false;
      });
    }
  }


  Future<void> _fetchSchedule() async {
    setState(() {
      _loadingSchedule = true;
      _scheduleError = null;
    });

    try {
      final response = await http.get(Uri.parse(_scheduleUrl));
      if (response.statusCode != 200) {
        throw Exception('فشل الاتصال: HTTP ${response.statusCode}');
      }

      final html = utf8.decode(response.bodyBytes);
      final rows = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true, caseSensitive: false)
          .allMatches(html);

      final items = <_ScheduleItem>[];
      for (final row in rows) {
        final rowHtml = row.group(1) ?? '';
        final cells = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true, caseSensitive: false)
            .allMatches(rowHtml)
            .map((m) => m.group(1) ?? '')
            .toList();

        if (cells.length < 4) continue;

        final locationHtml = cells[3];
        final urlMatch = RegExp(r'''href=["\']([^"\']+)["\']''', caseSensitive: false)
            .firstMatch(locationHtml);

        items.add(_ScheduleItem(
          lectureNumber: _cleanHtml(cells[0]),
          day: _cleanHtml(cells[1]),
          time: _cleanHtml(cells[2]),
          location: _cleanHtml(
            locationHtml.replaceAll(
              RegExp(r'<a\b[^>]*>.*?</a>', dotAll: true, caseSensitive: false),
              '',
            ),
          ),
          urlLocation: urlMatch?.group(1)?.trim() ?? '',
        ));
      }

      items.sort((a, b) => _parseLectureNumber(b.lectureNumber)
          .compareTo(_parseLectureNumber(a.lectureNumber)));

      if (!mounted) return;
      setState(() {
        _schedule = items;
        _loadingSchedule = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scheduleError = e.toString();
        _loadingSchedule = false;
      });
    }
  }

  // ─── Schedule data is loaded from the website ──────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub    = isDark ? Colors.white70 : Colors.black54;
    final cardBg     = isDark ? const Color(0xFF181818) : Colors.white;
    final bg         = isDark ? const Color(0xFF111111) : const Color(0xFFF7F3EC);

    return CustomScrollView(
      keyboardDismissBehavior:
    ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const BouncingScrollPhysics(),
      slivers: [
        PremiumAppBar(title: 'الدورات والمحاضرات', isDark: isDark),

        // ── Sticky Tab Bar ───────────────────────────────────────────────────
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabBarDelegate(
            tabController: _tabController,
            isDark: isDark,
            bg: bg,
          ),
        ),

        // ── Tab Body ────────────────────────────────────────────────────────
        SliverFillRemaining(
          child: TabBarView(
            controller: _tabController,
            children: [
              // ════════════════════════════════ TAB 1: COURSES ═════════════
              _CoursesTab(
                isDark: isDark,
                textPrimary: textPrimary,
                textSub: textSub,
                cardBg: cardBg,
                schedule: _schedule,
                loadingSchedule: _loadingSchedule,
                scheduleError: _scheduleError,
                onRetrySchedule: _fetchSchedule,
              ),

              // ════════════════════════════════ TAB 2: LECTURES ════════════
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
  }
}

class _ScheduleItem {
  final String lectureNumber;
  final String day;
  final String time;
  final String location;
  final String urlLocation;

  const _ScheduleItem({
    required this.lectureNumber,
    required this.day,
    required this.time,
    required this.location,
    required this.urlLocation,
  });
}

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
  const arabic = {'٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4', '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9'};
  var normalized = value;
  arabic.forEach((k, v) => normalized = normalized.replaceAll(k, v));
  return int.tryParse(normalized.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sticky Tab Bar Delegate
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
  Widget build(
      BuildContext ctx, double shrinkOffset, bool overlapsContent) {
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

  const _CoursesTab({
    required this.isDark,
    required this.textPrimary,
    required this.textSub,
    required this.cardBg,
    required this.schedule,
    required this.loadingSchedule,
    required this.scheduleError,
    required this.onRetrySchedule,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      children: [
        // ── Hero Banner ──────────────────────────────────────────────────────
// ── Course Card ──────────────────────────────────────────────────────
ClipRRect(
  borderRadius: BorderRadius.circular(28),
  child: Container(
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF111111) : const Color(0xFF1A1200),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: gold.withOpacity(0.18)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── صورة الدورة ──
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
            // تدرج داكن أسفل الصورة
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
            // شارة "دورة احترافية"
            Positioned(
              top: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
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
            // عنوان الدورة فوق الصورة
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
                  shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
              ),
            ),
          ],
        ),

        // ── جسم الكارت ──
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

              // الشرائح
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ChipBadge(
                    icon: Icons.access_time_rounded,
                    label: schedule.isNotEmpty ? '+${schedule.length} محاضرة' : '+25 محاضرة',
                  ),
                  const _ChipBadge(icon: Icons.people_rounded, label: ' للخريجين'),
                  const _ChipBadge(icon: Icons.verified_rounded, label: 'شهادة '),
                ],
              ),

              const SizedBox(height: 16),

              // زرّا الإجراء

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
        ),
      ],
    );
  }
}

class _ScheduleTable extends StatelessWidget {
  final List<_ScheduleItem> schedule;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final bool isDark;
  final Color textPrimary, textSub, cardBg;

  const _ScheduleTable({
    required this.schedule,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.isDark,
    required this.textPrimary,
    required this.textSub,
    required this.cardBg,
  });

  static const gold = Color(0xFFD4A017);

  Future<void> _openLocation(String rawUrl) async {
    if (rawUrl.trim().isEmpty) return;
    var value = rawUrl.trim();
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }
    final uri = Uri.parse(value);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
            Text('جارٍ تحميل جدول المحاضرات...', style: TextStyle(color: textSub, fontSize: 12.5)),
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
            Text('تعذّر جلب جدول المحاضرات', style: TextStyle(color: textPrimary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('إعادة المحاولة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        child: Text('لا توجد محاضرات حالياً', textAlign: TextAlign.center, style: TextStyle(color: textSub)),
      );
    }

    return Container(
      decoration: _boxDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFFD4A017), Color(0xFFB8860B)]),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            child: const Row(
              children: [
                _HeaderCell(text: '#', flex: 1),
                _HeaderCell(text: 'اليوم', flex: 2),
                _HeaderCell(text: 'الوقت', flex: 2),
                _HeaderCell(text: 'الموقع', flex: 3),
              ],
            ),
          ),
          ...schedule.asMap().entries.map((entry) {
            final i = entry.key;
            final row = entry.value;
            final isEven = i % 2 == 0;
            return Container(
              color: isEven
                  ? (isDark ? Colors.white.withOpacity(0.03) : const Color(0xFFFFF9EE))
                  : Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              child: Row(
                children: [
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
                        child: Text(row.lectureNumber, style: const TextStyle(color: gold, fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                  _DataCell(text: row.day, flex: 2, color: textPrimary),
                  _DataCell(text: row.time, flex: 2, color: textSub),
                  Expanded(
                    flex: 3,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          row.location.contains('أونلاين') || row.location.toLowerCase().contains('online')
                              ? Icons.videocam_rounded
                              : Icons.location_on_rounded,
                          size: 15,
                          color: row.urlLocation.isNotEmpty ? gold : const Color(0xFF43A047),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            row.location,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: textPrimary, fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (row.urlLocation.isNotEmpty) ...[
                          const SizedBox(width: 3),
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _openLocation(row.urlLocation),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: gold.withOpacity(0.14),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.map_rounded, color: gold, size: 15),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
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
        // Channel header
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
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${videos.length}',
                style: const TextStyle(
                    color: gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
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
Uri url = Uri.parse('https://www.youtube.com/watch?v=$videoId');
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
            // Thumbnail
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
                // Play overlay
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
                // Duration chip (placeholder)
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
                        style:
                            TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
              ],
            ),
            // Info
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
                              style: TextStyle(
                                  color: textSub, fontSize: 11),
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
    ), // ClipRRect
    ); // GestureDetector
  }
}
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
// ─────────────────────────────────────────────────────────────────────────────
// Helper Widgets
// ─────────────────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
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
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }
}