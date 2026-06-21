import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../widgets/shared_widgets.dart';

String _registrationPdfValue(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return '-';
}

String _registrationPdfFileName(String title) {
  final clean = title
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
      .replaceAll(RegExp(r'\s+'), '_')
      .trim();
  return '${clean.isEmpty ? 'registrations' : clean}.pdf';
}

Future<Uint8List> _buildRegistrationsPdfBytes({
  required List<Map<String, dynamic>> registrations,
  required String documentTitle,
  String archiveLabel = '',
}) async {
  final doc = pw.Document(version: PdfVersion.pdf_1_5, compress: true);

  pw.Font baseFont;
  pw.Font boldFont;
  try {
    baseFont = await PdfGoogleFonts.cairoRegular();
    boldFont = await PdfGoogleFonts.cairoBold();
  } catch (_) {
    baseFont = pw.Font.helvetica();
    boldFont = pw.Font.helveticaBold();
  }

  pw.MemoryImage? logo;
  try {
    final logoData = await rootBundle.load('assets/images/logo.png');
    logo = pw.MemoryImage(logoData.buffer.asUint8List());
  } catch (_) {
    logo = null;
  }

  pw.Widget text(
    String value, {
    double size = 10,
    bool bold = false,
    PdfColor? color,
    pw.TextAlign align = pw.TextAlign.center,
    double lineSpacing = 1.25,
  }) {
    return pw.Text(
      value,
      textDirection: pw.TextDirection.rtl,
      textAlign: align,
      style: pw.TextStyle(
        font: bold ? boldFont : baseFont,
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color,
        height: lineSpacing,
      ),
    );
  }

  pw.Widget cell(String value, {bool header = false}) {
    return pw.Container(
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: text(
        value.isEmpty ? '-' : value,
        size: header ? 10.5 : 9,
        bold: header,
        color: header ? PdfColors.white : PdfColor.fromHex('#211500'),
      ),
    );
  }

  final rows = registrations.asMap().entries.map((entry) {
    final index = entry.key + 1;
    final r = entry.value;
    return <String>[
      index.toString(),
      _registrationPdfValue(r, const ['full_name', 'name']),
      _registrationPdfValue(r, const ['email', 'account_email']),
      _registrationPdfValue(r, const ['certificate', 'specialization', 'major']),
      _registrationPdfValue(r, const ['graduation_year', 'grad_year']),
    ];
  }).toList();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 30),
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
      header: (context) => pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(bottom: 16),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logo != null)
                pw.Image(
                  logo!,
                  width: 58,
                  height: 58,
                  fit: pw.BoxFit.contain,
                ),
              if (logo != null) pw.SizedBox(height: 7),
              text('د. ماجد البنا', size: 18, bold: true, color: PdfColor.fromHex('#1A1000')),
              pw.SizedBox(height: 4),
              text('قائمة المسجلين بدورة تنمية مهندس الموقع', size: 12.5, bold: true, color: PdfColor.fromHex('#5F4108')),
              pw.SizedBox(height: 4),
              text(
                archiveLabel.trim().isEmpty
                    ? '$documentTitle • عدد المسجلين: ${registrations.length}'
                    : '$documentTitle • $archiveLabel • عدد المسجلين: ${registrations.length}',
                size: 9.5,
                color: PdfColor.fromHex('#5B5146'),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                width: 150,
                height: 1,
                color: PdfColor.fromHex('#D4A017'),
              ),
            ],
          ),
        ),
      ),
      footer: (context) => pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.only(top: 8),
          child: text('صفحة ${context.pageNumber} من ${context.pagesCount}', size: 8.5, color: PdfColor.fromHex('#7A705F')),
        ),
      ),
      build: (context) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Table(
            border: pw.TableBorder.all(color: PdfColor.fromHex('#D9C7A3'), width: 0.6),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.25),
              1: pw.FlexColumnWidth(2.4),
              2: pw.FlexColumnWidth(2.6),
              3: pw.FlexColumnWidth(3.0),
              4: pw.FlexColumnWidth(0.85),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColor.fromHex('#D4A017')),
                children: [
                  cell('سنة التخرج', header: true),
                  cell('الاختصاص', header: true),
                  cell('البريد الإلكتروني', header: true),
                  cell('الاسم', header: true),
                  cell('ت', header: true),
                ],
              ),
              ...rows.asMap().entries.map((entry) {
                final index = entry.key;
                final row = entry.value;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: index.isEven ? PdfColors.white : PdfColor.fromHex('#FFFCF5')),
                  children: [
                    cell(row[4]),
                    cell(row[3]),
                    cell(row[2]),
                    cell(row[1]),
                    cell(row[0]),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    ),
  );

  return doc.save();
}

Future<void> _openRegistrationsPdfInsideApp(
  BuildContext context, {
  required List<Map<String, dynamic>> registrations,
  required String documentTitle,
  String archiveLabel = '',
}) async {
  if (registrations.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('لا توجد بيانات لإنشاء ملف PDF.')),
    );
    return;
  }

  try {
    final bytes = await _buildRegistrationsPdfBytes(
      registrations: registrations,
      documentTitle: documentTitle,
      archiveLabel: archiveLabel,
    );
    await Printing.layoutPdf(
      name: _registrationPdfFileName(documentTitle),
      format: PdfPageFormat.a4,
      onLayout: (_) async => bytes,
    );
  } catch (_) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('تعذر إنشاء ملف PDF داخل التطبيق.')),
    );
  }
}
class CoursesPageDeepLinkBus {
  static final ValueNotifier<String?> requestedScheduleId =
      ValueNotifier<String?>(null);

  static void openSchedule(String scheduleId) {
    final id = scheduleId.trim();
    if (id.isEmpty) return;

    requestedScheduleId.value = null;
    requestedScheduleId.value = id;
  }
}
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

  final ScrollController _coursesScrollController = ScrollController();
  final Map<String, GlobalKey> _scheduleRowKeys = <String, GlobalKey>{};
  String? _highlightScheduleId;
  Timer? _clearHighlightTimer;

  void _syncScheduleRowKeys() {
    final ids = _schedule.map((e) => e.id).where((id) => id.isNotEmpty).toSet();
    _scheduleRowKeys.removeWhere((id, _) => !ids.contains(id));
    for (final id in ids) {
      _scheduleRowKeys.putIfAbsent(id, () => GlobalKey());
    }
  }

  void _handleScheduleDeepLink() {
    final id = CoursesPageDeepLinkBus.requestedScheduleId.value?.trim();
    if (id == null || id.isEmpty) return;
    _openScheduleFromNotification(id);
  }

  Future<void> _openScheduleFromNotification(String scheduleId) async {
    _clearHighlightTimer?.cancel();

    if (mounted) {
      setState(() {
        _highlightScheduleId = scheduleId;
        _syncScheduleRowKeys();
      });
    }

    _tabController.animateTo(0);

    if (_schedule.indexWhere((e) => e.id == scheduleId) == -1) {
      await _silentPollSchedule();
      if (!mounted) return;
      setState(_syncScheduleRowKeys);
    }

    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (!mounted) return;

      final rowContext = _scheduleRowKeys[scheduleId]?.currentContext;
      if (rowContext != null) {
        Scrollable.ensureVisible(
          rowContext,
          duration: const Duration(milliseconds: 850),
          curve: Curves.easeOutCubic,
          alignment: 0.42,
        );
      }

      _clearHighlightTimer?.cancel();
      _clearHighlightTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() => _highlightScheduleId = null);
      });
    });
  }

  bool _isSupervisor(User? user) {
    final email = user?.email?.trim().toLowerCase();
    return email == 'hmode.qq@gmail.com' || email == 'hmode.qu@gmail.com';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    CoursesPageDeepLinkBus.requestedScheduleId.addListener(_handleScheduleDeepLink);
    _fetchVideos();
    _fetchSchedule();
    _handleScheduleDeepLink();
    // بدء المراقبة الخفية كل 8 ثواني
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _silentPollSchedule();
    });
  }

  @override
  void dispose() {
    CoursesPageDeepLinkBus.requestedScheduleId.removeListener(_handleScheduleDeepLink);
    _clearHighlightTimer?.cancel();
    _pollTimer?.cancel();
    _coursesScrollController.dispose();
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
        _syncScheduleRowKeys();
        _loadingSchedule = false;
        _lastScheduleHash = _computeHash(cached);
      });
      if (_highlightScheduleId != null) {
        _openScheduleFromNotification(_highlightScheduleId!);
      }
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
    return items.map((e) => '${e.id}|${e.lectureNumber}|${e.day}|${e.time}|${e.location}|${e.urlLocation}').join(';');
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
          _syncScheduleRowKeys();
          _lastScheduleHash = hash;
        });
        if (_highlightScheduleId != null) {
          _openScheduleFromNotification(_highlightScheduleId!);
        }
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
      _syncScheduleRowKeys();
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
          _syncScheduleRowKeys();
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
      _syncScheduleRowKeys();
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
      setState(() {
        _schedule = backup;
        _syncScheduleRowKeys();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white70 : Colors.black54;
    final cardBg = isDark ? const Color(0xFF181818) : Colors.white;
    final bg = isDark ? const Color(0xFF111111) : const Color(0xFFF7F3EC);

    _syncScheduleRowKeys();

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final isAdmin = _isSupervisor(user);

        return NotificationListener<ScrollUpdateNotification>(
  onNotification: (notification) {
    if (notification.dragDetails != null) {
      final focus = FocusManager.instance.primaryFocus;
      if (focus != null && focus.hasFocus) {
        focus.unfocus();
      }
    }
    return false;
  },
  child: CustomScrollView(
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
                    user: user,
                    schedule: _schedule,
                    scrollController: _coursesScrollController,
                    highlightedScheduleId: _highlightScheduleId,
                    rowKeys: _scheduleRowKeys,
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
          ),
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
// Plain URL Launcher
// ─────────────────────────────────────────────────────────────────────────────
Uri? _safeUrl(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return null;

  final withScheme = trimmed.startsWith('http://') || trimmed.startsWith('https://')
      ? trimmed
      : 'https://$trimmed';

  return Uri.tryParse(withScheme);
}

Future<void> _openPlainUrl(BuildContext context, String rawUrl) async {
  final uri = _safeUrl(rawUrl);

  if (uri == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('رابط الموقع غير موجود')),
    );
    return;
  }

  try {
    final opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الرابط')),
      );
    }
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح الرابط')),
    );
  }
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
  final User? user;
  final List<_ScheduleItem> schedule;
  final ScrollController scrollController;
  final String? highlightedScheduleId;
  final Map<String, GlobalKey> rowKeys;
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
    required this.user,
    required this.schedule,
    required this.scrollController,
    required this.highlightedScheduleId,
    required this.rowKeys,
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
      controller: scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
        const SizedBox(height: 18),

        _RegistrationEntryCard(
          isDark: isDark,
          textPrimary: textPrimary,
          textSub: textSub,
          cardBg: cardBg,
          isAdmin: isAdmin,
          user: user,
          schedule: schedule,
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
          highlightScheduleId: highlightedScheduleId,
          rowKeys: rowKeys,
        ),

        const SizedBox(height: 20),

        _PreviousCoursesGalleryCard(
          isDark: isDark,
          textPrimary: textPrimary,
          textSub: textSub,
          cardBg: cardBg,
        ),

        const SizedBox(height: 20),

        _CertificateCard(
          isDark: isDark,
          textPrimary: textPrimary,
          textSub: textSub,
          cardBg: cardBg,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Add Box
// ─────────────────────────────────────────────────────────────────────────────
class _RegistrationEntryCard extends StatefulWidget {
  final bool isDark;
  final Color textPrimary, textSub, cardBg;
  final bool isAdmin;
  final User? user;
  final List<_ScheduleItem> schedule;

  const _RegistrationEntryCard({
    required this.isDark,
    required this.textPrimary,
    required this.textSub,
    required this.cardBg,
    required this.isAdmin,
    required this.user,
    required this.schedule,
  });

  @override
  State<_RegistrationEntryCard> createState() => _RegistrationEntryCardState();
}

class _RegistrationEntryCardState extends State<_RegistrationEntryCard> {
  static const _api = 'https://majidalbana.com/admin/registrations/registrations_api.php';
  bool _loading = true;
  bool _active = true;
  bool _registered = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final email = (widget.user?.email ?? '').trim().toLowerCase();
      final uri = Uri.parse('$_api?action=status&account_email=${Uri.encodeComponent(email)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _active = data['active'] == true || data['active'].toString() == '1';
        _registered = data['registered'] == true || data['registered'].toString() == '1';
        _message = data['message']?.toString();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'تعذر الاتصال بسيرفر التسجيل';
      });
    }
  }

Future<void> _openRegistration() async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RegistrationFormPage(
        isDark: widget.isDark,
        isAdmin: widget.isAdmin,
        user: widget.user,
        schedule: widget.schedule,
      ),
    ),
  );

  if (mounted) {
    _loadStatus();
  }
}

  @override
  Widget build(BuildContext context) {
    final gold = _CoursesTab.gold;
    final canOpen = widget.isAdmin || (_active && !_registered);
    final title = widget.isAdmin
        ? 'لوحة التسجيل في الاستمارة'
        : _registered
            ? 'تم تسجيلك في الاستمارة بنجاح'
            : _active
                ? 'استمارة التسجيل في دورة تنمية مهندس الموقع'
                : 'التسجيل في الاستمارة مغلق حالياً';

    final successGreen = _registered && !widget.isAdmin;
    final accent = successGreen ? Colors.green.shade600 : gold;

    return InkWell(
      onTap: canOpen ? _openRegistration : null,
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: successGreen
                ? (widget.isDark
                    ? [const Color(0xFF052E16), const Color(0xFF101010)]
                    : [const Color(0xFFE9FFF0), const Color(0xFFFFFFFF)])
                : (widget.isDark
                    ? [const Color(0xFF211600), const Color(0xFF101010)]
                    : [const Color(0xFFFFFBF2), const Color(0xFFFFE9B8)]),
          ),
          border: Border.all(color: accent.withOpacity(successGreen ? 0.55 : 0.35), width: successGreen ? 1.3 : 1),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(widget.isDark ? 0.12 : 0.20),
              blurRadius: successGreen ? 30 : 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withOpacity(0.15),
                border: Border.all(color: accent.withOpacity(0.42)),
              ),
              child: Icon(
                successGreen ? Icons.check_circle_rounded : (_registered ? Icons.verified_rounded : Icons.assignment_rounded),
                color: accent,
                size: 29,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: successGreen ? Colors.green.shade700 : widget.textPrimary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _loading
                        ? 'جاري التحقق من حالة التسجيل...'
                        : (successGreen ? 'تم استلام بياناتك بنجاح.' : (_message ?? 'اضغط لفتح صفحة التسجيل وإدخال البيانات المطلوبة.')),
                    style: TextStyle(
                      color: successGreen ? Colors.green.shade700.withOpacity(widget.isDark ? 0.85 : 0.78) : widget.textSub,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              canOpen ? Icons.arrow_back_ios_new_rounded : (successGreen ? Icons.done_all_rounded : Icons.lock_rounded),
              color: accent,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }}

class RegistrationFormPage extends StatefulWidget {
  final bool isDark;
  final bool isAdmin;
  final User? user;
  final List<_ScheduleItem> schedule;

  const RegistrationFormPage({
    super.key,
    required this.isDark,
    required this.isAdmin,
    required this.user,
    required this.schedule,
  });

  @override
  State<RegistrationFormPage> createState() => _RegistrationFormPageState();
}

class _RegistrationFormPageState extends State<RegistrationFormPage> {
  static const _api = 'https://majidalbana.com/admin/registrations/registrations_api.php';
  static const _pdfUrl = 'https://majidalbana.com/admin/registrations/export_current_pdf.php';
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _certificateCtrl = TextEditingController();
  final _governorateCtrl = TextEditingController();
  final _gradYearCtrl = TextEditingController();
  final _archiveNameCtrl = TextEditingController();
  final _registrationSearchCtrl = TextEditingController();

  bool _loading = true;
  bool _sending = false;
  bool _active = true;
  bool _registrationFieldsCollapsed = false;
  Map<String, dynamic>? _myRegistration;
  List<Map<String, dynamic>> _registrations = [];
  Timer? _registrationRefreshTimer;
  XFile? _photo;

  Color get _gold => const Color(0xFFD4A017);
  Color get _bg => widget.isDark ? const Color(0xFF101010) : const Color(0xFFF7F3EC);
  Color get _card => widget.isDark ? const Color(0xFF181818) : Colors.white;
  Color get _text => widget.isDark ? Colors.white : const Color(0xFF1A1000);
  Color get _sub => widget.isDark ? Colors.white70 : Colors.black54;
  String get _accountEmail => (widget.user?.email ?? _emailCtrl.text).trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = widget.user?.email ?? '';
    _loadRegistrationFoldState();
    _loadCachedRegistrationData();
    _load();
    if (widget.isAdmin) {
      _registrationRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _certificateCtrl.dispose();
    _governorateCtrl.dispose();
    _gradYearCtrl.dispose();
    _archiveNameCtrl.dispose();
    _registrationSearchCtrl.dispose();
    _registrationRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRegistrationFoldState() async {
    if (!widget.isAdmin) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool('registration_fields_collapsed_v1');
      if (!mounted || saved == null) return;
      setState(() => _registrationFieldsCollapsed = saved);
    } catch (_) {}
  }

  Future<void> _setRegistrationFieldsCollapsed(bool value) async {
    setState(() => _registrationFieldsCollapsed = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('registration_fields_collapsed_v1', value);
    } catch (_) {}
  }

  String get _registrationCacheKey => 'registration_form_cache_v3_${widget.isAdmin ? 'admin' : _accountEmail}';

  Future<void> _loadCachedRegistrationData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_registrationCacheKey);
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      if (!mounted) return;
      setState(() {
        _active = data['active'] == true || data['active'].toString() == '1';
        _myRegistration = data['registration'] is Map ? Map<String, dynamic>.from(data['registration'] as Map) : null;
        _registrations = data['registrations'] is List
            ? (data['registrations'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : <Map<String, dynamic>>[];
        _loading = false;
      });
    } catch (_) {}
  }

  Future<void> _saveRegistrationCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_registrationCacheKey, jsonEncode({
        'cached_at': DateTime.now().toIso8601String(),
        'active': _active,
        'registration': _myRegistration,
        'registrations': _registrations,
      }));
    } catch (_) {}
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final uri = Uri.parse('$_api?action=status&account_email=${Uri.encodeComponent(_accountEmail)}&with_list=${widget.isAdmin ? 1 : 0}');
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _active = data['active'] == true || data['active'].toString() == '1';
        _myRegistration = data['registration'] is Map ? Map<String, dynamic>.from(data['registration']) : null;
        _registrations = data['registrations'] is List
            ? (data['registrations'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
        _loading = false;
      });
      await _saveRegistrationCache();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent && _registrations.isEmpty && _myRegistration == null) {
        _toast('تعذر تحديث بيانات التسجيل. سيتم عرض آخر بيانات محفوظة عند توفرها.');
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1200,
    );
    if (picked != null && mounted) setState(() => _photo = picked);
  }

  void _keepFieldAboveKeyboard(BuildContext fieldContext) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        Scrollable.ensureVisible(
          fieldContext,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: 0.68,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
      });
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_photo == null) {
      _toast('يرجى اختيار صورة شخصية قبل إرسال الاستمارة.');
      return;
    }
    setState(() => _sending = true);
    try {
      final req = http.MultipartRequest('POST', Uri.parse(_api));
      req.fields.addAll({
        'action': 'submit',
        'account_email': _accountEmail,
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'full_name': _nameCtrl.text.trim(),
        'certificate': _certificateCtrl.text.trim(),
        'governorate': _governorateCtrl.text.trim(),
        'graduation_year': _gradYearCtrl.text.trim(),
      });
      req.files.add(await http.MultipartFile.fromPath('photo', _photo!.path));
      final streamed = await req.send().timeout(const Duration(seconds: 25));
      final body = await streamed.stream.bytesToString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['success'] == true) {
        setState(() {
          _myRegistration = Map<String, dynamic>.from(data['registration'] as Map);
          _sending = false;
        });
        await _saveRegistrationCache();
        _showSuccessDialog(_myRegistration!);
      } else {
        setState(() => _sending = false);
        _toast(data['message']?.toString() ?? 'فشل إرسال الاستمارة');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast('فشل الاتصال بالخادم');
    }
  }

  Future<void> _savePdf() async {
    await _openRegistrationsPdfInsideApp(
      context,
      registrations: _registrations,
      documentTitle: 'قائمة المسجلين الحالية',
      archiveLabel: 'الاستمارة الحالية',
    );
  }

  Future<void> _finishForm() async {
    _archiveNameCtrl.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: Text('إنهاء الاستمارة', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
        content: TextField(
          controller: _archiveNameCtrl,
          autofocus: true,
          style: TextStyle(color: _text),
          decoration: InputDecoration(
            labelText: 'اسم الاستمارة / المجلد',
            labelStyle: TextStyle(color: _sub),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('إنهاء')),
        ],
      ),
    );
    if (ok != true || _archiveNameCtrl.text.trim().isEmpty) return;
    await _adminAction('finish', {'archive_name': _archiveNameCtrl.text.trim()});
  }

  Future<void> _newForm() async {
    await _adminAction('new_form', {});
  }

  Future<void> _openAttendance() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AttendancePage(
          isDark: widget.isDark,
          schedule: widget.schedule,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openArchives() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RegistrationArchivesPage(isDark: widget.isDark),
      ),
    );
    if (mounted) _load();
  }

  Map<String, dynamic> _safeJson(String body) {
    final clean = body.trim();
    if (clean.isEmpty) {
      return {'success': false, 'message': 'لم يتم استلام رد صالح من الخادم.'};
    }
    try {
      final decoded = jsonDecode(clean);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {'success': false, 'message': 'رد الخادم غير مفهوم.'};
    } catch (_) {
      final preview = clean.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      return {
        'success': false,
        'message': preview.isEmpty
            ? 'الخادم رجّع رد غير صالح.'
            : 'الخادم رجّع خطأ غير JSON: ${preview.length > 140 ? preview.substring(0, 140) : preview}',
      };
    }
  }

  Future<void> _adminAction(String action, Map<String, String> extra) async {
    setState(() => _loading = true);
    try {
      final res = await http
          .post(
            Uri.parse(_api),
            headers: const {'Accept': 'application/json'},
            body: {'action': action, ...extra},
          )
          .timeout(const Duration(seconds: 75));
      final data = _safeJson(res.body);
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300 && data['success'] == true) {
        _toast(data['message']?.toString() ?? 'تم التنفيذ بنجاح');
        await _load();
      } else {
        setState(() => _loading = false);
        final msg = data['message']?.toString();
        _toast((msg == null || msg.isEmpty) ? 'فشل تنفيذ الأمر من الخادم HTTP ${res.statusCode}' : msg);
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('تأخر الخادم في معالجة الطلب. يرجى التحقق من صلاحيات مجلد الأرشيف عند تكرار المشكلة.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('تعذر تنفيذ الأمر: $e');
    }
  }

  void _showSuccessDialog(Map<String, dynamic> r) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _avatar(r, 76),
            const SizedBox(height: 12),
            Text('تم التسجيل بنجاح', style: TextStyle(color: _gold, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text(r['full_name']?.toString() ?? '', textAlign: TextAlign.center, style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text("${r['certificate'] ?? ''}\n${r['governorate'] ?? ''} - ${r['graduation_year'] ?? ''}", textAlign: TextAlign.center, style: TextStyle(color: _sub, height: 1.6)),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('تم'),
          ),
        ],
      ),
    );
  }

  Widget _avatar(Map<String, dynamic> r, double size) {
    final url = r['photo_url']?.toString() ?? '';
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: _gold.withOpacity(0.13),
        child: url.isEmpty
            ? Icon(Icons.person_rounded, color: _gold, size: size * 0.45)
            : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.person_rounded, color: _gold)),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon, {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c,
        keyboardType: keyboard,
        textInputAction: TextInputAction.next,
        style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: _gold),
          labelText: label,
          labelStyle: TextStyle(color: _sub),
          filled: true,
          fillColor: widget.isDark ? const Color(0xFF111111) : const Color(0xFFFAFAFA),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: _gold.withOpacity(0.18))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: _gold.withOpacity(0.18))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: _gold, width: 1.4)),
        ),
      ),
    );
  }

  Widget _pickedPhotoPreview() {
    if (_photo == null) {
      return Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _gold.withOpacity(0.12),
              border: Border.all(color: _gold.withOpacity(0.28)),
            ),
            child: Icon(Icons.add_a_photo_rounded, color: _gold, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'إرفاق صورة شخصية حديثة',
              style: TextStyle(color: _text, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        ClipOval(
          child: Image.file(
            File(_photo!.path),
            width: 68,
            height: 68,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('تم اختيار الصورة', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('انقر مرة اخرى على الصورة لتغييرها ', style: TextStyle(color: _sub, fontSize: 12, height: 1.45)),
            ],
          ),
        ),
        Icon(Icons.check_circle_rounded, color: Colors.green.shade600),
      ],
    );
  }

  Widget _registrationForm() {
    if (!_active && !widget.isAdmin) {
      return _stateBox(Icons.lock_rounded, 'انتهت الاستمارة', 'التسجيل مغلق حالياً.');
    }
    if (_myRegistration != null && !widget.isAdmin) {
      return _registeredBox(_myRegistration!);
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _gold.withOpacity(0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(widget.isDark ? 0.18 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            if (widget.isAdmin) ...[
              InkWell(
                onTap: () => _setRegistrationFieldsCollapsed(!_registrationFieldsCollapsed),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _gold.withOpacity(0.22)),
                  ),
                  child: Row(
                    children: [
                      Icon(_registrationFieldsCollapsed ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded, color: _gold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _registrationFieldsCollapsed ? 'فتح حقول التسجيل' : 'طي حقول التسجيل',
                          style: TextStyle(color: _text, fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        _registrationFieldsCollapsed ? 'مطوية' : 'مفتوحة',
                        style: TextStyle(color: _sub, fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 240),
              crossFadeState: widget.isAdmin && _registrationFieldsCollapsed ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              firstChild: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: widget.isDark ? const Color(0xFF111111) : const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _gold.withOpacity(0.10)),
                ),
                child: Text('حقول التسجيل مطوية ومحفوظة.', textAlign: TextAlign.center, style: TextStyle(color: _sub, fontWeight: FontWeight.w700)),
              ),
              secondChild: Column(
                children: [
                  _field(_nameCtrl, 'الاسم الثلاثي', Icons.badge_rounded),
                  _field(_certificateCtrl, 'الشهادة والاختصاص', Icons.school_rounded),
                  _field(_gradYearCtrl, 'سنة التخرج', Icons.date_range_rounded, keyboard: TextInputType.number),
                  _field(_phoneCtrl, 'رقم الهاتف PHONE', Icons.phone_rounded, keyboard: TextInputType.phone),
                  _field(_governorateCtrl, 'المحافظة', Icons.location_city_rounded),
                  _field(_emailCtrl, 'البريد الإلكتروني EMAIL', Icons.email_rounded, keyboard: TextInputType.emailAddress),
                  InkWell(
                    onTap: _pickPhoto,
                    borderRadius: BorderRadius.circular(22),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: (_photo == null ? _gold : Colors.green).withOpacity(0.35)),
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: _photo == null
                              ? [_gold.withOpacity(0.10), _gold.withOpacity(0.04)]
                              : [Colors.green.withOpacity(0.13), Colors.green.withOpacity(0.05)],
                        ),
                      ),
                      child: _pickedPhotoPreview(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _sending ? null : _submit,
                      icon: _sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
                      label: Text(_sending ? 'جاري الإرسال...' : 'إرسال الاستمارة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: const Color(0xFF1A1000),
                        elevation: 0,
                        shadowColor: _gold.withOpacity(0.35),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _registeredBox(Map<String, dynamic> r) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.green.withOpacity(0.35))),
      child: Row(
        children: [
          _avatar(r, 58),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('تم تسجيلك في الاستمارة بنجاح', style: TextStyle(color: Colors.green.shade600, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(r['full_name']?.toString() ?? '', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
              Text("${r['certificate'] ?? ''} • ${r['phone'] ?? ''}", style: TextStyle(color: _sub, height: 1.5)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _stateBox(IconData icon, String title, String msg) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(24), border: Border.all(color: _gold.withOpacity(0.16))),
      child: Row(children: [Icon(icon, color: _gold, size: 34), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: _text, fontWeight: FontWeight.w900)), const SizedBox(height: 6), Text(msg, style: TextStyle(color: _sub, height: 1.6))]))]),
    );
  }

  Widget _adminActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    required Color color,
    bool filled = false,
  }) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: enabled ? 1 : 0.48,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: filled ? color.withOpacity(0.18) : (widget.isDark ? const Color(0xFF111111) : const Color(0xFFFAFAFA)),
            border: Border.all(color: color.withOpacity(enabled ? 0.34 : 0.14)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: color.withOpacity(0.14),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _sub, fontSize: 10.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _adminPanel() {
    if (!widget.isAdmin) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _gold.withOpacity(0.22)),
        boxShadow: [
          BoxShadow(
            color: _gold.withOpacity(widget.isDark ? 0.08 : 0.10),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: _gold.withOpacity(0.13),
              border: Border.all(color: _gold.withOpacity(0.20)),
            ),
            child: Icon(Icons.admin_panel_settings_rounded, color: _gold, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('لوحة تحكم الاستمارة', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 14))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: _active ? Colors.green.withOpacity(0.14) : Colors.red.withOpacity(0.14),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: (_active ? Colors.green : Colors.red).withOpacity(0.20)),
            ),
            child: Text(_active ? 'مفتوحة' : 'منتهية', style: TextStyle(color: _active ? Colors.green.shade600 : Colors.red.shade500, fontWeight: FontWeight.w900, fontSize: 10)),
          ),
        ]),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 3.25,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            _adminActionTile(
              icon: Icons.add_circle_rounded,
              title: 'استمارة جديدة',
              subtitle: _active ? 'بعد الإنهاء فقط' : 'ابدأ دورة جديدة',
              onTap: _active ? null : _newForm,
              color: Colors.green.shade600,
            ),
            _adminActionTile(
              icon: Icons.stop_circle_rounded,
              title: 'إنهاء الاستمارة',
              subtitle: _active ? 'حفظ كأرشيف' : 'منتهية حالياً',
              onTap: _active ? _finishForm : null,
              color: Colors.red.shade500,
              filled: true,
            ),
            _adminActionTile(
              icon: Icons.folder_special_rounded,
              title: 'الاستمارات السابقة',
              subtitle: 'أرشيف المجلدات',
              onTap: _openArchives,
              color: _gold,
            ),
            _adminActionTile(
              icon: Icons.fact_check_rounded,
              title: 'الحضور',
              subtitle: 'تحديد المحاضرات',
              onTap: _openAttendance,
              color: _gold,
              filled: true,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _gold.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            _active
                ? 'الاستمارة الجديدة تتفعل فقط بعد إنهاء الحالية.'
                : 'الاستمارة منتهية. يمكنك إنشاء استمارة جديدة الآن أو فتح الأرشيف السابق.',
            style: TextStyle(color: _sub, fontSize: 11, height: 1.45, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }

  String _valueOf(Map<String, dynamic> r, String key) {
    final v = r[key]?.toString().trim() ?? '';
    return v.isEmpty ? 'غير مضاف' : v;
  }

  void _showRegistrationDetails(Map<String, dynamic> r) {
    final rows = <MapEntry<String, String>>[
      MapEntry('الاسم الثلاثي', _valueOf(r, 'full_name')),
      MapEntry('الشهادة والاختصاص', _valueOf(r, 'certificate')),
      MapEntry('سنة التخرج', _valueOf(r, 'graduation_year')),
      MapEntry('المحافظة', _valueOf(r, 'governorate')),
      MapEntry('رقم الهاتف', _valueOf(r, 'phone')),
      MapEntry('البريد الإلكتروني', _valueOf(r, 'email')),
      MapEntry('عدد الحضور', _valueOf(r, 'attendance_count')),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: _gold.withOpacity(0.22)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 44, height: 4, decoration: BoxDecoration(color: _sub.withOpacity(0.35), borderRadius: BorderRadius.circular(99))),
                const SizedBox(height: 16),
                _avatar(r, 82),
                const SizedBox(height: 10),
                Text(_valueOf(r, 'full_name'), textAlign: TextAlign.center, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(height: 14),
                ...rows.map((e) => Container(
                      margin: const EdgeInsets.only(bottom: 9),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        color: widget.isDark ? const Color(0xFF111111) : const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _gold.withOpacity(0.08)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 112, child: Text(e.key, style: TextStyle(color: _sub, fontWeight: FontWeight.w800, fontSize: 12))),
                          Expanded(child: Text(e.value, style: TextStyle(color: _text, fontWeight: FontWeight.w900, height: 1.45))),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _adminList() {
    if (!widget.isAdmin) return const SizedBox.shrink();
    final query = _registrationSearchCtrl.text.trim().toLowerCase();
    final shown = query.isEmpty
        ? _registrations
        : _registrations.where((r) => (r['full_name']?.toString().toLowerCase() ?? '').contains(query)).toList();

    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _gold.withOpacity(0.16)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Expanded(
              child: Text('المسجلون حالياً (${shown.length}/${_registrations.length})', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            Tooltip(
              message: 'حفظ PDF للبيانات الحالية',
              child: InkWell(
                onTap: _savePdf,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _gold.withOpacity(0.22)),
                  ),
                  child: Icon(Icons.print_rounded, color: _gold, size: 19),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _registrationSearchCtrl,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search_rounded, color: _gold),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _registrationSearchCtrl.clear();
                      setState(() {});
                    },
                    icon: Icon(Icons.close_rounded, color: _sub),
                  ),
            hintText: 'أبحث عن اسم ..',
            hintStyle: TextStyle(color: _sub, fontWeight: FontWeight.w600),
            filled: true,
            fillColor: widget.isDark ? const Color(0xFF111111) : const Color(0xFFFAFAFA),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: _gold.withOpacity(0.16))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: _gold.withOpacity(0.16))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: _gold, width: 1.3)),
          ),
        ),
        const SizedBox(height: 12),
        if (_registrations.isEmpty)
          Text('لا توجد تسجيلات حالياً.', style: TextStyle(color: _sub))
        else if (shown.isEmpty)
          Text('لا توجد نتائج لهذا الاسم. حتى البحث تعب من البشر.', style: TextStyle(color: _sub))
        else
          ...shown.map((r) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: widget.isDark ? const Color(0xFF111111) : const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _gold.withOpacity(0.08)),
                ),
                child: Row(children: [
                  _avatar(r, 44),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r['full_name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 13.5)),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.how_to_reg_rounded, color: Colors.green.shade600, size: 15),
                            const SizedBox(width: 5),
                            Text('عدد الحضور: ${r['attendance_count'] ?? 0}', style: TextStyle(color: _sub, fontSize: 11.5, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'تفاصيل المسجل',
                    child: InkWell(
                      onTap: () => _showRegistrationDetails(r),
                      borderRadius: BorderRadius.circular(13),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _gold.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: _gold.withOpacity(0.20)),
                        ),
                        child: Icon(Icons.info_outline_rounded, color: _gold, size: 18),
                      ),
                    ),
                  ),
                ]),
              )),
      ]),
    );
  }

  Widget _formHeroHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: widget.isDark
              ? [const Color(0xFF221700), const Color(0xFF111111)]
              : [const Color(0xFFFFF5DF), Colors.white],
        ),
        border: Border.all(color: _gold.withOpacity(0.22)),
        boxShadow: [
          BoxShadow(
            color: _gold.withOpacity(widget.isDark ? 0.08 : 0.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/courseforma.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [_gold.withOpacity(0.24), _gold.withOpacity(0.06)],
                        ),
                      ),
                      child: Icon(Icons.engineering_rounded, color: _gold, size: 54),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withOpacity(0.72)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                   
                        const SizedBox(height: 9),
                        const Text(
                          'استمارة التسجيل في دورة تنمية مهندس الموقع',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'املأ البيانات المطلوبة بدقة، وارفق صورة شخصية حديثة.',
            style: TextStyle(color: _sub, height: 1.7, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          title: Text('استمارة التسجيل', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
          iconTheme: IconThemeData(color: _text),
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: _gold))
            : ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  _formHeroHeader(),
                  const SizedBox(height: 16),
                  _adminPanel(),
                  _registrationForm(),
                  _adminList(),
                ],
              ),
      ),
    );
  }
}


class RegistrationArchivesPage extends StatefulWidget {
  final bool isDark;
  const RegistrationArchivesPage({super.key, required this.isDark});

  @override
  State<RegistrationArchivesPage> createState() => _RegistrationArchivesPageState();
}

class _RegistrationArchivesPageState extends State<RegistrationArchivesPage> {
  static const _api = 'https://majidalbana.com/admin/registrations/registrations_api.php';

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _archives = [];

  Color get _gold => const Color(0xFFD4A017);
  Color get _bg => widget.isDark ? const Color(0xFF101010) : const Color(0xFFF7F3EC);
  Color get _card => widget.isDark ? const Color(0xFF181818) : Colors.white;
  Color get _text => widget.isDark ? Colors.white : const Color(0xFF1A1000);
  Color get _sub => widget.isDark ? Colors.white70 : Colors.black54;

  @override
  void initState() {
    super.initState();
    _loadArchivesCache();
    _loadArchives();
  }

  Map<String, dynamic> _safeJson(String body) {
    final clean = body.trim();
    if (clean.isEmpty) return {'success': false, 'message': 'الخادم رجع رد فارغ.'};
    try {
      final decoded = jsonDecode(clean);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {'success': false, 'message': 'رد الخادم غير مفهوم.'};
    } catch (_) {
      final preview = clean.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      return {'success': false, 'message': preview.isEmpty ? 'رد الخادم غير صالح.' : preview};
    }
  }

  static const String _archivesCacheKey = 'registration_archives_cache_v2';

  Future<void> _loadArchivesCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_archivesCacheKey);
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw);
      if (data is! List) return;
      if (!mounted) return;
      setState(() {
        _archives = data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
        _error = null;
      });
    } catch (_) {}
  }

  Future<void> _saveArchivesCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_archivesCacheKey, jsonEncode(_archives));
    } catch (_) {}
  }

  Future<void> _loadArchives() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse('$_api?action=archives')).timeout(const Duration(seconds: 18));
      final data = _safeJson(res.body);
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300 && data['success'] == true) {
        setState(() {
          _archives = data['archives'] is List
              ? (data['archives'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
              : [];
          _loading = false;
        });
        await _saveArchivesCache();
      } else {
        setState(() {
          _loading = false;
          _error = data['message']?.toString() ?? 'فشل جلب الاستمارات السابقة.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر الاتصال بخادم الأرشيف: $e';
      });
    }
  }

  Future<void> _openArchive(Map<String, dynamic> archive) async {
    final name = archive['name']?.toString() ?? '';
    if (name.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RegistrationArchiveDetailsPage(isDark: widget.isDark, archiveName: name),
      ),
    );
  }

  Future<Map<String, dynamic>> _postArchiveAction(Map<String, String> body) async {
    final res = await http.post(Uri.parse(_api), body: body).timeout(const Duration(seconds: 25));
    final data = _safeJson(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300 || data['success'] != true) {
      throw Exception(data['message']?.toString() ?? 'فشل تنفيذ العملية.');
    }
    return data;
  }

Future<void> _renameArchive(Map<String, dynamic> archive) async {
  final oldName = archive['name']?.toString() ?? '';
  if (oldName.isEmpty) return;

  final newName = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final ctrl = TextEditingController(text: oldName);

      return AlertDialog(
        backgroundColor: _card,
        title: Text(
          'تعديل اسم الأرشيف',
          style: TextStyle(color: _text, fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: _text),
          decoration: InputDecoration(
            labelText: 'اسم الأرشيف',
            labelStyle: TextStyle(color: _sub),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = ctrl.text.trim();
              Navigator.pop(dialogContext, value);
            },
            child: const Text('حفظ'),
          ),
        ],
      );
    },
  );

  if (newName == null || newName.isEmpty || newName == oldName) return;

  try {
    await _postArchiveAction({
      'action': 'archive_rename',
      'archive_name': oldName,
      'new_name': newName,
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تعديل اسم الأرشيف بنجاح.')),
    );

    await _loadArchives();
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذر تعديل اسم الأرشيف: $e')),
    );
  }
}

  Future<void> _deleteArchive(Map<String, dynamic> archive) async {
    final name = archive['name']?.toString() ?? '';
    if (name.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: Text('حذف الأرشيف', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
        content: Text('سيتم حذف الأرشيف وبياناته المحفوظة نهائياً.\n$name', style: TextStyle(color: _sub, height: 1.7)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _postArchiveAction({'action': 'archive_delete', 'archive_name': name});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الأرشيف بنجاح.')));
      await _loadArchives();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حذف الأرشيف: $e')));
    }
  }

  Future<void> _showArchiveOptions(Map<String, dynamic> archive) async {
    final name = archive['name']?.toString() ?? 'أرشيف';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(Icons.drive_file_rename_outline_rounded, color: _gold),
                title: Text('تعديل اسم الأرشيف', style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
                onTap: () { Navigator.pop(context); _renameArchive(archive); },
              ),
              ListTile(
                leading: Icon(Icons.delete_forever_rounded, color: Colors.red.shade400),
                title: Text('حذف الأرشيف وبياناته', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.w900)),
                onTap: () { Navigator.pop(context); _deleteArchive(archive); },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _folderCard(Map<String, dynamic> a, int index) {
    final count = a['registrations_count']?.toString() ?? '0';
    final date = a['archived_at']?.toString() ?? '';
    final name = a['name']?.toString() ?? 'استمارة محفوظة';
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 260 + (index * 45).clamp(0, 360)),
      tween: Tween(begin: 0, end: 1),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(offset: Offset(0, 18 * (1 - value)), child: child),
        );
      },
      child: InkWell(
        onTap: () => _openArchive(a),
        onLongPress: () => _showArchiveOptions(a),
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _gold.withOpacity(0.18)),
            boxShadow: [
              BoxShadow(color: _gold.withOpacity(widget.isDark ? 0.07 : 0.12), blurRadius: 24, offset: const Offset(0, 14)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [_gold.withOpacity(0.95), const Color(0xFFFFE7A0)]),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(18),
                      ),
                    ),
                    child: const Icon(Icons.folder_rounded, color: Color(0xFF1A1000), size: 32),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_back_ios_new_rounded, color: _gold, size: 17),
                ],
              ),
              const SizedBox(height: 14),
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 15, height: 1.35)),
              const SizedBox(height: 8),
              Text('عدد المسجلين: $count', style: TextStyle(color: _sub, fontSize: 12, fontWeight: FontWeight.w700)),
              if (date.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(date, style: TextStyle(color: _sub, fontSize: 11)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.folder_off_rounded, color: _gold, size: 58),
          const SizedBox(height: 12),
          Text('لا توجد استمارات سابقة', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 8),
          Text('عند إنهاء الاستمارة الحالية سيظهر أرشيفها هنا داخل التطبيق.', textAlign: TextAlign.center, style: TextStyle(color: _sub, height: 1.6)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          title: Text('الاستمارات السابقة', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
          iconTheme: IconThemeData(color: _text),
          actions: [IconButton(onPressed: _loadArchives, icon: Icon(Icons.refresh_rounded, color: _gold))],
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: _gold))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.error_outline_rounded, color: Colors.red.shade400, size: 50),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: _text, height: 1.6)),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(onPressed: _loadArchives, icon: const Icon(Icons.refresh_rounded), label: const Text('إعادة المحاولة')),
                      ]),
                    ),
                  )
                : _archives.isEmpty
                    ? _emptyState()
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.86,
                        ),
                        itemCount: _archives.length,
                        itemBuilder: (_, i) => _folderCard(_archives[i], i),
                      ),
      ),
    );
  }
}

class RegistrationArchiveDetailsPage extends StatefulWidget {
  final bool isDark;
  final String archiveName;

  const RegistrationArchiveDetailsPage({super.key, required this.isDark, required this.archiveName});

  @override
  State<RegistrationArchiveDetailsPage> createState() => _RegistrationArchiveDetailsPageState();
}

class _RegistrationArchiveDetailsPageState extends State<RegistrationArchiveDetailsPage> {
  static const _api = 'https://majidalbana.com/admin/registrations/registrations_api.php';

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _registrations = [];
  List<Map<String, dynamic>> _attendance = [];
  String _archivedAt = '';

  Color get _gold => const Color(0xFFD4A017);
  Color get _bg => widget.isDark ? const Color(0xFF101010) : const Color(0xFFF7F3EC);
  Color get _card => widget.isDark ? const Color(0xFF181818) : Colors.white;
  Color get _text => widget.isDark ? Colors.white : const Color(0xFF1A1000);
  Color get _sub => widget.isDark ? Colors.white70 : Colors.black54;

  @override
  void initState() {
    super.initState();
    _loadDetailsCache();
    _loadDetails();
  }

  Map<String, dynamic> _safeJson(String body) {
    final clean = body.trim();
    if (clean.isEmpty) return {'success': false, 'message': 'الخادم رجع رد فارغ.'};
    try {
      final decoded = jsonDecode(clean);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {'success': false, 'message': 'رد الخادم غير مفهوم.'};
    } catch (_) {
      final preview = clean.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      return {'success': false, 'message': preview.isEmpty ? 'رد الخادم غير صالح.' : preview};
    }
  }

  String get _detailCacheKey => 'registration_archive_detail_cache_v2_${widget.archiveName}';

  Future<void> _loadDetailsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_detailCacheKey);
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      if (!mounted) return;
      setState(() {
        _registrations = data['registrations'] is List
            ? (data['registrations'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : <Map<String, dynamic>>[];
        _attendance = data['attendance'] is List
            ? (data['attendance'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : <Map<String, dynamic>>[];
        _archivedAt = data['archived_at']?.toString() ?? '';
        _loading = false;
      });
    } catch (_) {}
  }

  Future<void> _saveDetailsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_detailCacheKey, jsonEncode({
        'archived_at': _archivedAt,
        'registrations': _registrations,
        'attendance': _attendance,
      }));
    } catch (_) {}
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('$_api?action=archive_detail&archive_name=${Uri.encodeComponent(widget.archiveName)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 18));
      final data = _safeJson(res.body);
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300 && data['success'] == true) {
        setState(() {
          _registrations = data['registrations'] is List
              ? (data['registrations'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
              : [];
          _attendance = data['attendance'] is List
              ? (data['attendance'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
              : [];
          _archivedAt = data['archived_at']?.toString() ?? '';
          _loading = false;
        });
        await _saveDetailsCache();
      } else {
        setState(() {
          _loading = false;
          _error = data['message']?.toString() ?? 'فشل فتح الاستمارة السابقة.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر الاتصال بخادم الأرشيف: $e';
      });
    }
  }

  Future<void> _saveArchivePdf() async {
    await _openRegistrationsPdfInsideApp(
      context,
      registrations: _registrations,
      documentTitle: 'قائمة المسجلين - ${widget.archiveName}',
      archiveLabel: _archivedAt.isEmpty ? widget.archiveName : '${widget.archiveName} • $_archivedAt',
    );
  }

  Widget _personCard(Map<String, dynamic> r) {
    final name = r['full_name']?.toString() ?? '';
    final cert = r['certificate']?.toString() ?? '';
    final phone = r['phone']?.toString() ?? '';
    final email = r['email']?.toString() ?? '';
    final attendance = r['attendance_count']?.toString() ?? '0';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(20), border: Border.all(color: _gold.withOpacity(0.14))),
      child: Row(children: [
        ClipOval(
  child: Container(
    width: 52,
    height: 52,
    color: _gold.withOpacity(0.13),
    child: (() {
      final url = r['photo_url']?.toString().trim() ?? '';
      if (url.isEmpty) {
        return Icon(Icons.person_rounded, color: _gold, size: 28);
      }

      return Image.network(
        url,
        fit: BoxFit.cover,
        headers: const {
          'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
        },
        errorBuilder: (_, __, ___) {
          return Icon(Icons.person_rounded, color: _gold, size: 28);
        },
      );
    })(),
  ),
),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('$cert • $phone\n$email\nالحضور: $attendance', style: TextStyle(color: _sub, fontSize: 12, height: 1.45)),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          title: Text(widget.archiveName, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 17)),
          iconTheme: IconThemeData(color: _text),
          actions: [
            Tooltip(
              message: 'طباعة / حفظ PDF',
              child: IconButton(
                onPressed: _saveArchivePdf,
                icon: Icon(Icons.print_rounded, color: _gold),
              ),
            ),
          ],
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: _gold))
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: _text, height: 1.6))))
                : ListView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(colors: widget.isDark ? [const Color(0xFF221700), const Color(0xFF121212)] : [const Color(0xFFFFF5DF), Colors.white]),
                          border: Border.all(color: _gold.withOpacity(0.2)),
                        ),
                        child: Row(children: [
                          Icon(Icons.folder_open_rounded, color: _gold, size: 38),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('أرشيف ${widget.archiveName}', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 16)),
                            const SizedBox(height: 6),
                            Text('عدد المسجلين: ${_registrations.length}${_archivedAt.isNotEmpty ? ' • $_archivedAt' : ''}\nسجلات الحضور: ${_attendance.length}', style: TextStyle(color: _sub, height: 1.55)),
                          ])),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'طباعة / حفظ PDF',
                            child: InkWell(
                              onTap: _saveArchivePdf,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: _gold.withOpacity(0.13),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _gold.withOpacity(0.24)),
                                ),
                                child: Icon(Icons.print_rounded, color: _gold, size: 21),
                              ),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      if (_registrations.isEmpty)
                        Text('هذا الأرشيف فارغ.', style: TextStyle(color: _sub))
                      else
                        ..._registrations.map(_personCard),
                    ],
                  ),
      ),
    );
  }
}


class AttendancePage extends StatefulWidget {
  final bool isDark;
  final List<_ScheduleItem> schedule;

  const AttendancePage({
    super.key,
    required this.isDark,
    required this.schedule,
  });

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  static const _api = 'https://majidalbana.com/admin/registrations/registrations_api.php';
  final _searchCtrl = TextEditingController();
  _ScheduleItem? _selectedLecture;
  bool _loading = false;
  bool _saving = false;
  List<Map<String, dynamic>> _registrations = [];
  final Set<int> _presentIds = <int>{};
  Timer? _attendanceSyncTimer;

  Color get _gold => const Color(0xFFD4A017);
  Color get _bg => widget.isDark ? const Color(0xFF101010) : const Color(0xFFF7F3EC);
  Color get _card => widget.isDark ? const Color(0xFF181818) : Colors.white;
  Color get _text => widget.isDark ? Colors.white : const Color(0xFF1A1000);
  Color get _sub => widget.isDark ? Colors.white70 : Colors.black54;

  @override
  void initState() {
    super.initState();
    _flushPendingAttendance(silent: true);
    _attendanceSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) => _flushPendingAttendance(silent: true));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _attendanceSyncTimer?.cancel();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _attendanceCacheKey(String scheduleId) => 'attendance_cache_v3_$scheduleId';
  static const String _attendancePendingKey = 'attendance_pending_queue_v3';

  Future<Map<String, dynamic>?> _pendingAttendanceFor(String scheduleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_attendancePendingKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final item = decoded[scheduleId];
      return item is Map ? Map<String, dynamic>.from(item) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveAttendanceCache(_ScheduleItem lecture) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_attendanceCacheKey(lecture.id), jsonEncode({
        'cached_at': DateTime.now().toIso8601String(),
        'schedule_id': lecture.id,
        'registrations': _registrations,
        'present_ids': _presentIds.toList(),
      }));
    } catch (_) {}
  }

  Future<bool> _loadAttendanceCache(_ScheduleItem lecture) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_attendanceCacheKey(lecture.id));
      if (raw == null || raw.isEmpty) return false;
      final data = jsonDecode(raw);
      if (data is! Map) return false;
      final regs = data['registrations'] is List
          ? (data['registrations'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      final ids = data['present_ids'] is List
          ? (data['present_ids'] as List).map((e) => int.tryParse(e.toString()) ?? 0).where((id) => id > 0).toSet()
          : <int>{};
      final pending = await _pendingAttendanceFor(lecture.id);
      final pendingIds = pending != null && pending['present_ids'] is List
          ? (pending['present_ids'] as List).map((e) => int.tryParse(e.toString()) ?? 0).where((id) => id > 0).toSet()
          : null;
      if (!mounted) return false;
      setState(() {
        _registrations = regs;
        _presentIds
          ..clear()
          ..addAll(pendingIds ?? ids);
        _loading = false;
      });
      return regs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _queueAttendanceSave(_ScheduleItem lecture) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_attendancePendingKey);
      final queue = raw == null || raw.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      queue[lecture.id] = {
        'schedule_id': lecture.id,
        'present_ids': _presentIds.toList(),
        'queued_at': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_attendancePendingKey, jsonEncode(queue));
    } catch (_) {}
  }

  Future<bool> _sendAttendanceToServer(String scheduleId, Set<int> presentIds) async {
    final res = await http.post(
      Uri.parse(_api),
      body: {
        'action': 'attendance_save',
        'schedule_id': scheduleId,
        'present_ids': jsonEncode(presentIds.toList()),
      },
    ).timeout(const Duration(seconds: 20));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return res.statusCode >= 200 && res.statusCode < 300 && data['success'] == true;
  }

  Future<void> _flushPendingAttendance({bool silent = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_attendancePendingKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded.isEmpty) return;
      final queue = Map<String, dynamic>.from(decoded);
      final done = <String>[];
      for (final entry in queue.entries) {
        final item = entry.value;
        if (item is! Map) continue;
        final ids = item['present_ids'] is List
            ? (item['present_ids'] as List).map((e) => int.tryParse(e.toString()) ?? 0).where((id) => id > 0).toSet()
            : <int>{};
        final ok = await _sendAttendanceToServer(entry.key, ids);
        if (ok) done.add(entry.key);
      }
      if (done.isEmpty) return;
      for (final key in done) queue.remove(key);
      await prefs.setString(_attendancePendingKey, jsonEncode(queue));
      if (!silent && mounted) _toast('تمت مزامنة الحضور المحفوظ محلياً.');
    } catch (_) {}
  }

  Future<void> _loadAttendance(_ScheduleItem lecture) async {
    setState(() {
      _selectedLecture = lecture;
      _loading = true;
      _registrations = [];
      _presentIds.clear();
      _searchCtrl.clear();
    });
    await _loadAttendanceCache(lecture);
    await _flushPendingAttendance(silent: true);
    try {
      final uri = Uri.parse('$_api?action=attendance_get&schedule_id=${Uri.encodeComponent(lecture.id)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300 && data['success'] == true) {
        final regs = data['registrations'] is List
            ? (data['registrations'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : <Map<String, dynamic>>[];
        final pending = await _pendingAttendanceFor(lecture.id);
        final pendingIds = pending != null && pending['present_ids'] is List
            ? (pending['present_ids'] as List).map((e) => int.tryParse(e.toString()) ?? 0).where((id) => id > 0).toSet()
            : null;
        setState(() {
          _registrations = regs;
          _presentIds
            ..clear()
            ..addAll(pendingIds ?? regs.where((r) => r['present'] == true || r['present'].toString() == '1').map((r) => int.tryParse(r['id'].toString()) ?? 0).where((id) => id > 0));
          _loading = false;
        });
        await _saveAttendanceCache(lecture);
      } else {
        setState(() => _loading = false);
        if (_registrations.isEmpty) _toast(data['message']?.toString() ?? 'تعذر جلب بيانات الحضور.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (_registrations.isEmpty) {
        _toast('تعذر الاتصال بالخادم. سيتم استخدام آخر نسخة محفوظة عند توفرها.');
      }
    }
  }

  Future<void> _saveAttendance() async {
    if (_selectedLecture == null) return;
    final lecture = _selectedLecture!;
    setState(() => _saving = true);
    await _saveAttendanceCache(lecture);
    try {
      final ok = await _sendAttendanceToServer(lecture.id, _presentIds);
      if (!mounted) return;
      setState(() => _saving = false);
      if (ok) {
        _toast('تم حفظ الحضور بنجاح.');
        await _flushPendingAttendance(silent: true);
        await _loadAttendance(lecture);
      } else {
        await _queueAttendanceSave(lecture);
        _toast('تم حفظ الحضور محلياً، وستتم المزامنة عند توفر الاتصال.');
      }
    } catch (_) {
      await _queueAttendanceSave(lecture);
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('تم حفظ الحضور محلياً، وستتم المزامنة عند توفر الاتصال.');
    }
  }

  Widget _avatar(Map<String, dynamic> r, double size) {
    final url = r['photo_url']?.toString() ?? '';
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: _gold.withOpacity(0.13),
        child: url.isEmpty
            ? Icon(Icons.person_rounded, color: _gold, size: size * 0.45)
            : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.person_rounded, color: _gold)),
      ),
    );
  }

  void _showAttendanceRegistrationDetails(Map<String, dynamic> r) {
    final rows = <MapEntry<String, String>>[
      MapEntry('الاسم الثلاثي', _attendanceValueOf(r, 'full_name')),
      MapEntry('الشهادة والاختصاص', _attendanceValueOf(r, 'certificate')),
      MapEntry('سنة التخرج', _attendanceValueOf(r, 'graduation_year')),
      MapEntry('المحافظة', _attendanceValueOf(r, 'governorate')),
      MapEntry('رقم الهاتف', _attendanceValueOf(r, 'phone')),
      MapEntry('البريد الإلكتروني', _attendanceValueOf(r, 'email')),
      MapEntry('عدد الحضور', _attendanceValueOf(r, 'attendance_count')),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: _gold.withOpacity(0.22)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 44, height: 4, decoration: BoxDecoration(color: _sub.withOpacity(0.35), borderRadius: BorderRadius.circular(99))),
                const SizedBox(height: 16),
                _avatar(r, 82),
                const SizedBox(height: 10),
                Text(_attendanceValueOf(r, 'full_name'), textAlign: TextAlign.center, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(height: 14),
                ...rows.map((e) => Container(
                      margin: const EdgeInsets.only(bottom: 9),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        color: widget.isDark ? const Color(0xFF111111) : const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _gold.withOpacity(0.08)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 112, child: Text(e.key, style: TextStyle(color: _sub, fontWeight: FontWeight.w800, fontSize: 12))),
                          Expanded(child: Text(e.value, style: TextStyle(color: _text, fontWeight: FontWeight.w900, height: 1.45))),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _attendanceValueOf(Map<String, dynamic> r, String key) {
    final v = r[key]?.toString().trim() ?? '';
    return v.isEmpty ? 'غير مضاف' : v;
  }

  Widget _lecturePicker() {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _gold.withOpacity(0.18)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('اختيار المحاضرة', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 8),
            Text('يرجى اختيار المحاضرة من الجدول لعرض قائمة المسجلين وتثبيت الحضور.', style: TextStyle(color: _sub, height: 1.7)),
          ]),
        ),
        const SizedBox(height: 14),
        if (widget.schedule.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(22)),
            child: Text('لا توجد محاضرات في الجدول حالياً.', style: TextStyle(color: _sub)),
          )
        else
          ...widget.schedule.map((lecture) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _gold.withOpacity(0.16)),
                ),
                child: ListTile(
                  onTap: () => _loadAttendance(lecture),
                  leading: CircleAvatar(
                    backgroundColor: _gold.withOpacity(0.16),
                    child: Text(lecture.lectureNumber, style: TextStyle(color: _gold, fontWeight: FontWeight.w900)),
                  ),
                  title: Text('المحاضرة ${lecture.lectureNumber}', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                  subtitle: Text('${lecture.day} • ${lecture.time}\n${lecture.location}', style: TextStyle(color: _sub, height: 1.5)),
                  trailing: Icon(Icons.arrow_back_ios_new_rounded, color: _gold, size: 18),
                ),
              )),
      ],
    );
  }

  Widget _attendanceList() {
    final q = _searchCtrl.text.trim().toLowerCase();
    final shown = q.isEmpty
        ? _registrations
        : _registrations.where((r) {
            final name = (r['full_name'] ?? '').toString().toLowerCase();
            return name.contains(q);
          }).toList();

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _gold.withOpacity(0.18)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: _gold.withOpacity(0.16),
                child: Text(_selectedLecture!.lectureNumber, style: TextStyle(color: _gold, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('حضور المحاضرة ${_selectedLecture!.lectureNumber}', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 3),
                Text('${_selectedLecture!.day} • ${_selectedLecture!.time}', style: TextStyle(color: _sub)),
              ])),
              TextButton.icon(onPressed: () => setState(() => _selectedLecture = null), icon: const Icon(Icons.swap_horiz_rounded), label: const Text('تغيير')),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: _text),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, color: _gold),
                hintText: 'بحث بالاسم فقط',
                hintStyle: TextStyle(color: _sub),
                filled: true,
                fillColor: widget.isDark ? const Color(0xFF111111) : const Color(0xFFFAFAFA),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: _gold.withOpacity(0.18))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: _gold.withOpacity(0.18))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: _gold, width: 1.4)),
              ),
            ),
            const SizedBox(height: 10),
            Text('الحاضرون المحددون: ${_presentIds.length} من ${_registrations.length}', style: TextStyle(color: _sub, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 14),
        if (_loading)
          Center(child: Padding(padding: const EdgeInsets.all(26), child: CircularProgressIndicator(color: _gold)))
        else if (shown.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(22)),
            child: Text('لا توجد نتائج.', style: TextStyle(color: _sub)),
          )
        else
          ...shown.map((r) {
            final id = int.tryParse(r['id'].toString()) ?? 0;
            final present = _presentIds.contains(id);
            return InkWell(
              onTap: () {
                setState(() {
                  if (present) {
                    _presentIds.remove(id);
                  } else {
                    _presentIds.add(id);
                  }
                });
                if (_selectedLecture != null) _saveAttendanceCache(_selectedLecture!);
              },
              onLongPress: () => _showAttendanceRegistrationDetails(r),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: present ? _gold.withOpacity(widget.isDark ? 0.16 : 0.12) : _card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: present ? _gold.withOpacity(0.55) : _gold.withOpacity(0.14)),
                ),
                child: Row(
                  children: [
                    _avatar(r, 42),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r['full_name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 13.5)),
                          const SizedBox(height: 3),
                          Text('عدد الحضور: ${r['attendance_count'] ?? 0}', style: TextStyle(color: _sub, fontSize: 11.5, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: present ? _gold : Colors.transparent,
                        border: Border.all(color: present ? _gold : _gold.withOpacity(0.38), width: 1.6),
                      ),
                      child: present ? const Icon(Icons.check_rounded, color: Color(0xFF1A1000), size: 19) : null,
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          title: Text('الحضور', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
          iconTheme: IconThemeData(color: _text),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              if (_selectedLecture != null) {
                setState(() => _selectedLecture = null);
              } else {
                Navigator.of(context).maybePop();
              }
            },
          ),
          actions: [
            if (_selectedLecture != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: TextButton.icon(
                  onPressed: _saving ? null : _saveAttendance,
                  icon: _saving
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _gold))
                      : Icon(Icons.save_rounded, color: _gold),
                  label: Text(_saving ? 'حفظ...' : 'حفظ', style: TextStyle(color: _gold, fontWeight: FontWeight.w900)),
                ),
              ),
          ],
        ),
        body: _selectedLecture == null ? _lecturePicker() : _attendanceList(),
      ),
    );
  }
}


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

  final _numFocus = FocusNode();
  final _dayFocus = FocusNode();
  final _timeFocus = FocusNode();
  final _locFocus = FocusNode();
  final _urlFocus = FocusNode();

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
    _numFocus.dispose();
    _dayFocus.dispose();
    _timeFocus.dispose();
    _locFocus.dispose();
    _urlFocus.dispose();
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

  void _keepFieldAboveKeyboard(BuildContext fieldContext) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        Scrollable.ensureVisible(
          fieldContext,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: 0.60,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
      });
    });
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
                          focusNode: _numFocus,
                          onFocused: _keepFieldAboveKeyboard,
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
                          focusNode: _dayFocus,
                          onFocused: _keepFieldAboveKeyboard,
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
                          focusNode: _timeFocus,
                          onFocused: _keepFieldAboveKeyboard,
                          label: 'الوقت',
                          icon: Icons.access_time_rounded,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _AdminField(
                          controller: _locCtrl,
                          focusNode: _locFocus,
                          onFocused: _keepFieldAboveKeyboard,
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
                          focusNode: _urlFocus,
                          onFocused: _keepFieldAboveKeyboard,
                          label: 'رابط الموقع (اختياري)',
                          icon: Icons.link_rounded,
                          isDark: isDark,
                          keyboardType: TextInputType.url,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _openPlainUrl(context, _urlCtrl.text.trim()),
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
class _AdminField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<BuildContext>? onFocused;
  final String label;
  final IconData icon;
  final bool isDark;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _AdminField({
    required this.controller,
    this.focusNode,
    this.onFocused,
    required this.label,
    required this.icon,
    required this.isDark,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  State<_AdminField> createState() => _AdminFieldState();
}

class _AdminFieldState extends State<_AdminField> {
  static const gold = Color(0xFFD4A017);
  FocusNode? _ownedFocusNode;

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    _ownedFocusNode = widget.focusNode == null ? FocusNode() : null;
    _effectiveFocusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _AdminField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldEffectiveFocusNode = oldWidget.focusNode ?? _ownedFocusNode;
    if (oldWidget.focusNode != widget.focusNode) {
      oldEffectiveFocusNode?.removeListener(_handleFocusChange);
      if (widget.focusNode == null) {
        _ownedFocusNode ??= FocusNode();
      } else {
        _ownedFocusNode?.dispose();
        _ownedFocusNode = null;
      }
      _effectiveFocusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_effectiveFocusNode.hasFocus) {
      widget.onFocused?.call(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return TextField(
      focusNode: _effectiveFocusNode,
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      textAlign: TextAlign.right,
      onTap: () => widget.onFocused?.call(context),
      scrollPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      style: TextStyle(
        color: isDark ? Colors.white : const Color(0xFF1A1000),
        fontSize: 13,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: TextStyle(
          color: gold.withOpacity(0.7),
          fontSize: 12,
        ),
        prefixIcon: Icon(widget.icon, color: gold, size: 18),
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
final String? highlightScheduleId;
final Map<String, GlobalKey> rowKeys;

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
  this.highlightScheduleId,
  this.rowKeys = const {},
});

  static const gold = Color(0xFFD4A017);

  void _openLocation(BuildContext context, _ScheduleItem item) {
    _openPlainUrl(context, item.urlLocation);
  }
  Future<void> _showEditDialog(
    BuildContext context,
    _ScheduleItem item,
    int index,
  ) async {
    final numCtrl = TextEditingController(text: item.lectureNumber);
    final dayCtrl = TextEditingController(text: item.day);
    final timeCtrl = TextEditingController(text: item.time);
    final locCtrl = TextEditingController(text: item.location);
    final urlCtrl = TextEditingController(text: item.urlLocation);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _EditBottomSheet(
          isDark: isDark,
          item: item,
          numCtrl: numCtrl,
          dayCtrl: dayCtrl,
          timeCtrl: timeCtrl,
          locCtrl: locCtrl,
          urlCtrl: urlCtrl,
          onSave: (newItem) => onEdit(item, newItem),
          onDelete: () => onDelete(item.id),
        );
      },
    );

    numCtrl.dispose();
    dayCtrl.dispose();
    timeCtrl.dispose();
    locCtrl.dispose();
    urlCtrl.dispose();
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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
    final isHighlighted =
        highlightScheduleId != null && row.id == highlightScheduleId;
    final baseColor = isEven
        ? (isDark ? Colors.white.withOpacity(0.03) : const Color(0xFFFFF9EE))
        : Colors.transparent;

    return AnimatedContainer(
      key: rowKeys[row.id] ?? ValueKey(row.id),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      color: baseColor,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (isHighlighted)
            Positioned.fill(
              child: _MovingLectureHighlight(isDark: isDark),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: Row(
              children: [
                if (isAdmin)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: gold.withOpacity(0.45),
                      size: 18,
                    ),
                  ),
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
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                _DataCell(text: row.day, flex: 2, color: textPrimary),
                _DataCell(text: row.time, flex: 2, color: textSub),
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
                              fontWeight: FontWeight.w600,
                            ),
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
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (row.urlLocation.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        GestureDetector(
                          onTap: () => _openLocation(context, row),
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
                          color: gold.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        color: gold,
                        size: 13,
                      ),
                    ),
                  ),
              ],
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

class _MovingLectureHighlight extends StatefulWidget {
  final bool isDark;

  const _MovingLectureHighlight({required this.isDark});

  @override
  State<_MovingLectureHighlight> createState() => _MovingLectureHighlightState();
}

class _MovingLectureHighlightState extends State<_MovingLectureHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _LectureRowShinePainter(
                progress: _controller.value,
                isDark: widget.isDark,
              ),
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }
}

class _LectureRowShinePainter extends CustomPainter {
  final double progress;
  final bool isDark;

  const _LectureRowShinePainter({
    required this.progress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final rect = Offset.zero & size;

    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
        colors: [
          const Color(0xFF0D47A1).withOpacity(isDark ? 0.10 : 0.055),
          const Color(0xFF2196F3).withOpacity(isDark ? 0.22 : 0.13),
          const Color(0xFF64B5F6).withOpacity(isDark ? 0.18 : 0.10),
          const Color(0xFF2196F3).withOpacity(isDark ? 0.22 : 0.13),
          const Color(0xFF0D47A1).withOpacity(isDark ? 0.10 : 0.055),
        ],
        stops: const [0.0, 0.22, 0.50, 0.78, 1.0],
      ).createShader(rect);

    canvas.drawRect(rect, basePaint);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF81D4FA).withOpacity(isDark ? 0.26 : 0.17),
          const Color(0xFF29B6F6).withOpacity(isDark ? 0.12 : 0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromLTWH(
        -size.width * 0.08,
        -size.height * 1.2,
        size.width * 1.16,
        size.height * 3.4,
      ));

    canvas.drawRect(rect, glowPaint);

    final sweepWidth = math.max(140.0, size.width * 0.34);
    final travel = size.width + sweepWidth * 2;
    final centerX = -sweepWidth + (progress * travel);

    void drawBeam(double x, double opacityScale) {
      final beamRect = Rect.fromLTWH(
        x - sweepWidth / 2,
        -size.height * 0.65,
        sweepWidth,
        size.height * 2.3,
      );

      final beamPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            const Color(0xFF03A9F4).withOpacity(0.00),
            const Color(0xFF40C4FF).withOpacity((isDark ? 0.20 : 0.14) * opacityScale),
            const Color(0xFFB3E5FC).withOpacity((isDark ? 0.78 : 0.58) * opacityScale),
            Colors.white.withOpacity((isDark ? 0.72 : 0.50) * opacityScale),
            const Color(0xFFB3E5FC).withOpacity((isDark ? 0.70 : 0.50) * opacityScale),
            const Color(0xFF40C4FF).withOpacity((isDark ? 0.18 : 0.12) * opacityScale),
            const Color(0xFF03A9F4).withOpacity(0.00),
            Colors.transparent,
          ],
          stops: const [0.0, 0.18, 0.33, 0.45, 0.50, 0.55, 0.67, 0.82, 1.0],
        ).createShader(beamRect);

      canvas.save();
      canvas.clipRect(rect);
      canvas.translate(x, size.height / 2);
      canvas.rotate(-0.16);
      canvas.translate(-x, -size.height / 2);
      canvas.drawRect(beamRect, beamPaint);
      canvas.restore();
    }

    drawBeam(centerX, 1.0);

    final previousX = centerX - travel;
    if (previousX + sweepWidth > 0) {
      drawBeam(previousX, 1.0);
    }

    final nextX = centerX + travel;
    if (nextX - sweepWidth < size.width) {
      drawBeam(nextX, 1.0);
    }

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
        colors: [
          const Color(0xFF03A9F4).withOpacity(0.05),
          const Color(0xFF4FC3F7).withOpacity(isDark ? 0.45 : 0.28),
          const Color(0xFF03A9F4).withOpacity(0.05),
        ],
      ).createShader(rect);

    canvas.drawRect(rect.deflate(0.6), borderPaint);
  }

  @override
  bool shouldRepaint(covariant _LectureRowShinePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isDark != isDark;
  }
}

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
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                          onTap: () => _openPlainUrl(context, widget.urlCtrl.text.trim()),
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


class _PreviousCoursesGalleryCard extends StatefulWidget {
  final bool isDark;
  final Color textPrimary;
  final Color textSub;
  final Color cardBg;

  const _PreviousCoursesGalleryCard({
    required this.isDark,
    required this.textPrimary,
    required this.textSub,
    required this.cardBg,
  });

  @override
  State<_PreviousCoursesGalleryCard> createState() =>
      _PreviousCoursesGalleryCardState();
}

class _PreviousCoursesGalleryCardState
    extends State<_PreviousCoursesGalleryCard>
    with SingleTickerProviderStateMixin {
  static const gold = Color(0xFFD4A017);
  static const List<String> _courseImages = [
    'https://majidalbana.com/img/imagesfromcourses/1.jpg',
    'https://majidalbana.com/img/imagesfromcourses/2.jpg',
    'https://majidalbana.com/img/imagesfromcourses/3.jpg',
    'https://majidalbana.com/img/imagesfromcourses/4.jpg',
    'https://majidalbana.com/img/imagesfromcourses/5.jpg',
    'https://majidalbana.com/img/imagesfromcourses/6.jpg',
    'https://majidalbana.com/img/imagesfromcourses/7.jpg',
    'https://majidalbana.com/img/imagesfromcourses/8.jpg',
    'https://majidalbana.com/img/imagesfromcourses/9.jpg',
    'https://majidalbana.com/img/imagesfromcourses/10.jpg',
    'https://majidalbana.com/img/imagesfromcourses/11.jpg',
  ];

  late final AnimationController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4300),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (!mounted) return;
          setState(() => _index = (_index + 1) % _courseImages.length);
          _controller.forward(from: 0);
        }
      })
      ..forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final url in _courseImages) {
      precacheImage(NetworkImage(url), context);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildAnimatedImage(String url, double progress) {
    final eased = Curves.easeInOutCubic.transform(progress);
    final mode = _index % 7;

    double scale = 1.18;
    double dx = 0;
    double dy = 0;
    double angle = 0;

    switch (mode) {
      case 0:
        scale = 1.22 - (eased * 0.035);
        dx = -16 + (eased * 32);
        break;
      case 1:
        scale = 1.19 + (eased * 0.045);
        dy = 14 - (eased * 28);
        break;
      case 2:
        scale = 1.23 - (eased * 0.05);
        dx = 12 - (eased * 24);
        dy = -8 + (eased * 16);
        break;
      case 3:
        scale = 1.20 + (math.sin(eased * math.pi) * 0.035);
        angle = (-0.010 + (eased * 0.020));
        break;
      case 4:
        scale = 1.21;
        dx = math.sin(eased * math.pi * 2) * 12;
        dy = math.cos(eased * math.pi * 2) * 7;
        break;
      case 5:
        scale = 1.24 - (eased * 0.04);
        dx = -10 + (eased * 20);
        dy = 10 - (eased * 20);
        angle = 0.008 - (eased * 0.016);
        break;
      default:
        scale = 1.19 + (eased * 0.035);
        dx = 18 - (eased * 36);
        break;
    }

    return ClipRect(
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Transform.rotate(
          angle: angle,
          child: Transform.scale(
            scale: scale,
            child: SizedBox.expand(
              child: Image.network(
                url,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
                loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: widget.isDark
                        ? const [Color(0xFF161616), Color(0xFF080808)]
                        : const [Color(0xFFFFF8E8), Color(0xFFFFEDC2)],
                  ),
                ),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: gold,
                  ),
                ),
              );
            },
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: widget.isDark
                          ? const [Color(0xFF1B1B1B), Color(0xFF090909)]
                          : const [Color(0xFFFFF5DD), Color(0xFFFFE3A3)],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: widget.textSub.withOpacity(0.75),
                    size: 36,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCinemaOverlay(double progress) {
    final mode = _index % 7;
    final glowShift = -1.2 + (progress * 2.4);
    final pulse = Curves.easeInOut.transform(math.sin(progress * math.pi));

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.05),
                Colors.transparent,
                Colors.black.withOpacity(widget.isDark ? 0.32 : 0.22),
              ],
            ),
          ),
        ),
        if (mode == 1 || mode == 4 || mode == 6)
          Transform.translate(
            offset: Offset(glowShift * 260, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.white.withOpacity(0.10),
                    const Color(0xFFFFD86B).withOpacity(0.12),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.43, 0.50, 1.0],
                ),
              ),
            ),
          ),
        if (mode == 2 || mode == 5)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(
                  -0.8 + (progress * 1.6),
                  -0.6 + (math.sin(progress * math.pi) * 0.45),
                ),
                radius: 0.9,
                colors: [
                  Colors.white.withOpacity(0.16 * pulse),
                  const Color(0xFFFFD86B).withOpacity(0.06 * pulse),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Row(
            children: List.generate(_courseImages.length, (i) {
              final active = i == _index;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 450),
                  height: active ? 4 : 3,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: active
                        ? gold.withOpacity(0.95)
                        : Colors.white.withOpacity(0.28),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: gold.withOpacity(0.55),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: gold.withOpacity(0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(widget.isDark ? 0.24 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: gold.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                Expanded(
                  child: Text(
                    'صور من الدورات السابقة',
                    style: TextStyle(
                      color: widget.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: gold.withOpacity(widget.isDark ? 0.18 : 0.14),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: gold.withOpacity(0.28)),
                  ),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => Text(
                      '${_index + 1}/${_courseImages.length}',
                      style: TextStyle(
                        color: widget.isDark ? const Color(0xFFFFE3A1) : gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                decoration: BoxDecoration(
                  color: widget.isDark
                      ? const Color(0xFF111111)
                      : const Color(0xFFFFFBF4),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final progress = _controller.value;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 850),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final slide = Tween<Offset>(
                                begin: Offset(_index.isEven ? 0.18 : -0.18, 0),
                                end: Offset.zero,
                              ).animate(animation);
                              final scale = Tween<double>(
                                begin: 1.04,
                                end: 1.0,
                              ).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: slide,
                                  child: ScaleTransition(
                                    scale: scale,
                                    child: child,
                                  ),
                                ),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey(_courseImages[_index]),
                              child: _buildAnimatedImage(
                                _courseImages[_index],
                                progress,
                              ),
                            ),
                          ),
                          IgnorePointer(child: _buildCinemaOverlay(progress)),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.38),
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.16),
                                ),
                              ),
                              child: const Text(
                                'لقطات واقعية',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CertificateCard extends StatefulWidget {
  final bool isDark;
  final Color textPrimary;
  final Color textSub;
  final Color cardBg;

  const _CertificateCard({
    required this.isDark,
    required this.textPrimary,
    required this.textSub,
    required this.cardBg,
  });

  @override
  State<_CertificateCard> createState() => _CertificateCardState();
}

class _CertificateCardState extends State<_CertificateCard>
    with SingleTickerProviderStateMixin {
  static const gold = Color(0xFFD4A017);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: gold.withOpacity(0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(widget.isDark ? 0.24 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: gold.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                Expanded(
                  child: Text(
                    'شهادة المشاركة',
                    style: TextStyle(
                      color: widget.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD86B), Color(0xFFD4A017)],
                    ),
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: gold.withOpacity(0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Text(
                    'مميزة',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
    
            const SizedBox(height: 14),

            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                decoration: BoxDecoration(
                  color: widget.isDark
                      ? const Color(0xFF141414)
                      : const Color(0xFFFFFBF5),
                ),
                child: AspectRatio(
                  aspectRatio: 18 / 12,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/images/cer.jpg',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFF2B1D00),
                                Color(0xFF120D00),
                              ],
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.image_not_supported_rounded,
                            color: Colors.white54,
                            size: 38,
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
                                Colors.white.withOpacity(0.04),
                                Colors.transparent,
                                Colors.black.withOpacity(0.10),
                              ],
                            ),
                          ),
                        ),
                      ),

                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _controller,
                            builder: (context, _) {
                              return CustomPaint(
                                painter: _CertificateEdgeLightPainter(
                                  progress: _controller.value,
                                  gold: gold,
                                  isDark: widget.isDark,
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
          

                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CertificateEdgeLightPainter extends CustomPainter {
  final double progress;
  final Color gold;
  final bool isDark;

  _CertificateEdgeLightPainter({
    required this.progress,
    required this.gold,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final rect = Rect.fromLTWH(
      5,
      5,
      size.width - 10,
      size.height - 10,
    );

    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(20),
    );

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final metric = metrics.first;
    final totalLength = metric.length;
    final head = progress * totalLength;
    final lightLength = totalLength * 0.28;
    const pieces = 22;
    final pieceLength = lightLength / pieces;

    double normalize(double value) {
      value %= totalLength;
      if (value < 0) value += totalLength;
      return value;
    }

    void drawWrappedPath({
      required double from,
      required double to,
      required Paint paint,
    }) {
      final start = normalize(from);
      final end = normalize(to);

      if (start <= end) {
        canvas.drawPath(metric.extractPath(start, end), paint);
      } else {
        canvas.drawPath(metric.extractPath(start, totalLength), paint);
        canvas.drawPath(metric.extractPath(0, end), paint);
      }
    }

    final idleBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..color = gold.withOpacity(isDark ? 0.28 : 0.22);
    canvas.drawRRect(rrect, idleBorderPaint);

    for (int i = pieces - 1; i >= 0; i--) {
      final localProgress = 1.0 - (i / pieces);
      final opacity = Curves.easeOutCubic.transform(localProgress);
      final from = head - ((i + 1) * pieceLength);
      final to = head - (i * pieceLength);

      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 11
        ..color = gold.withOpacity(0.035 + (opacity * 0.20))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

      final softPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 5.5
        ..color = const Color(0xFFFFE8A6).withOpacity(0.04 + (opacity * 0.34))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

      final corePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2.2
        ..color = Colors.white.withOpacity(0.05 + (opacity * 0.58));

      drawWrappedPath(from: from, to: to, paint: glowPaint);
      drawWrappedPath(from: from, to: to, paint: softPaint);
      drawWrappedPath(from: from, to: to, paint: corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CertificateEdgeLightPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.gold != gold ||
        oldDelegate.isDark != isDark;
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
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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