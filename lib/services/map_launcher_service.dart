import 'package:flutter/material.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
class MapLauncherService {
  /// استخراج إحداثيات من أي رابط نصي
  static Map<String, double>? extractCoords(String url) {
    final patterns = [
      RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'[?&]q=(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'll=(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)'),
      RegExp(r'/(-?\d+\.\d+),(-?\d+\.\d+)'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(url);
      if (m != null) {
        final lat = double.tryParse(m.group(1)!);
        final lng = double.tryParse(m.group(2)!);
        if (lat != null && lng != null &&
            lat >= -90 && lat <= 90 &&
            lng >= -180 && lng <= 180) {
          return {'lat': lat, 'lng': lng};
        }
      }
    }
    return null;
  }

  /// فتح Bottom Sheet
  static Future<void> openMapPicker({
    required BuildContext context,
    required String rawUrl,
    bool isDark = false,
  }) async {
    if (rawUrl.trim().isEmpty) return;

    final url = rawUrl.trim()
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');

    // ── محاولة استخراج مباشر ──
    Map<String, double>? coords = extractCoords(url);

    if (coords == null) {
      // ── استخراج عبر WebView ──
      if (!context.mounted) return;
      coords = await _extractCoordsViaWebView(context, url, isDark)
    .timeout(const Duration(seconds: 3), onTimeout: () => null);
    }
// إذا فشل استخراج الإحداثيات، افتح الرابط مباشرة
if (coords == null) {
  final uri = Uri.tryParse(url);
  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  return;
}
    if (!context.mounted) return;

    List<AvailableMap> availableMaps = [];
    try {
      availableMaps = await MapLauncher.installedMaps;
    } catch (_) {}

    if (!context.mounted) return;

    if (availableMaps.isEmpty) {
      _showNoAppsDialog(context, isDark);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MapPickerSheet(
        availableMaps: availableMaps,
        coords: coords,
        rawUrl: url,
        isDark: isDark,
      ),
    );
  }

  /// استخراج الإحداثيات عبر WebView مخفي
static Future<Map<String, double>?> _extractCoordsViaWebView(
    BuildContext context,
    String url,
    bool isDark,
  ) async {
    if (!context.mounted) return null;

    // أظهر loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                    color: Color(0xFFD4A017), strokeWidth: 3),
              ),
              SizedBox(height: 14),
              Text('جارٍ تحديد الموقع...',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );

    Map<String, double>? result;

    try {
      // ── استخدام Places API لحل الرابط المختصر ──
      const apiKey = 'AIzaSyDwiUw3uEO5xqafhsfMZ0KVFYUhQ9hvmh8';

      // طلب GET مع follow redirects للحصول على الرابط النهائي
String current = url;
for (int i = 0; i < 2; i++) {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 2);

  final req = await client.getUrl(Uri.parse(current));
  req.followRedirects = false;
  req.headers.set('User-Agent',
      'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36');

  final resp = await req.close();

  // قراءة الـ body للبحث عن روابط بإحداثيات
  final body = await resp.transform(utf8.decoder).join();
  client.close();

  result = extractCoords(current);
  if (result != null) break;

  // ابحث في الـ body عن روابط Google Maps
  final urlsInBody = RegExp(r'https://www\.google\.com/maps[^\s"<>]+')
      .allMatches(body)
      .map((m) => m.group(0)!)
      .toList();
  for (final u in urlsInBody) {
    result = extractCoords(u);
    if (result != null) break;
  }
  if (result != null) break;

  // تابع الـ redirect يدوياً وتجاهل Dynamic Links
  if (resp.statusCode >= 300 && resp.statusCode < 400) {
    final location = resp.headers.value('location');
    if (location == null || location.contains('dynamiclinks')) break;
    current = location.startsWith('http')
        ? location
        : Uri.parse(current).resolve(location).toString();
  } else {
    break;
  }
}

      // إذا فشل، جرب Places API بالـ CID أو Place ID
      if (result == null) {
final cidMatch = RegExp(r'cid=(\d+)').firstMatch(current);
final placeIdMatch =
    RegExp(r'place/[^/]+/([A-Za-z0-9_-]+)').firstMatch(current);

        String? placeId = placeIdMatch?.group(1);

        if (placeId != null) {
          final resp = await http.get(Uri.parse(
            'https://maps.googleapis.com/maps/api/place/details/json'
            '?place_id=$placeId&fields=geometry&key=$apiKey',
          )).timeout(const Duration(seconds: 2));

          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body);
            final loc = data['result']?['geometry']?['location'];
            if (loc != null) {
              result = {
                'lat': (loc['lat'] as num).toDouble(),
                'lng': (loc['lng'] as num).toDouble(),
              };
            }
          }
        } else if (cidMatch != null) {
          final cid = cidMatch.group(1);
          final resp = await http.get(Uri.parse(
            'https://maps.googleapis.com/maps/api/place/details/json'
            '?cid=$cid&fields=geometry&key=$apiKey',
          )).timeout(const Duration(seconds: 2));

          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body);
            final loc = data['result']?['geometry']?['location'];
            if (loc != null) {
              result = {
                'lat': (loc['lat'] as num).toDouble(),
                'lng': (loc['lng'] as num).toDouble(),
              };
            }
          }
        }
      }
    } catch (_) {}

    // أغلق loading
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    return result;
  }

  static void _showNoAppsDialog(BuildContext context, bool isDark) {
    const gold = Color(0xFFD4A017);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.map_outlined, color: gold),
            SizedBox(width: 10),
            Text('لا توجد تطبيقات خرائط',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(
          'لم يتم العثور على أي تطبيق خرائط مثبت.',
          style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً', style: TextStyle(color: gold)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WebView مخفي لاستخراج الإحداثيات
// ─────────────────────────────────────────────────────────────────────────────
class _CoordExtractorDialog extends StatefulWidget {
  final String url;
  final bool isDark;
  final ValueChanged<Map<String, double>> onCoordsFound;
  final VoidCallback onTimeout;

  const _CoordExtractorDialog({
    required this.url,
    required this.isDark,
    required this.onCoordsFound,
    required this.onTimeout,
  });

  @override
  State<_CoordExtractorDialog> createState() => _CoordExtractorDialogState();
}

class _CoordExtractorDialogState extends State<_CoordExtractorDialog> {
  late final WebViewController _controller;
  bool _done = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onUrlChange: (change) {
          final newUrl = change.url ?? '';
          _tryExtract(newUrl);
        },
        onPageStarted: (startedUrl) {
          _tryExtract(startedUrl);
        },
        onPageFinished: (finishedUrl) {
          _tryExtract(finishedUrl);
          _controller.runJavaScriptReturningResult('window.location.href')
              .then((result) {
            _tryExtract(result.toString().replaceAll('"', ''));
          });
          _controller.runJavaScriptReturningResult(
            'document.querySelector("link[rel=canonical]")?.href ?? ""'
          ).then((result) {
            final canonical = result.toString().replaceAll('"', '');
            if (canonical.isNotEmpty) _tryExtract(canonical);
          });
          _controller.runJavaScriptReturningResult(
            r'''
            (function() {
              var metas = document.querySelectorAll("meta");
              for (var i = 0; i < metas.length; i++) {
                var content = metas[i].getAttribute("content") || "";
                if (content.includes("maps.google") || content.includes("@")) {
                  return content;
                }
              }
              var links = document.querySelectorAll("a[href]");
              for (var i = 0; i < links.length; i++) {
                var href = links[i].getAttribute("href") || "";
                if (href.includes("maps.google") || href.includes("@")) {
                  return href;
                }
              }
              return window.location.href;
            })()
            '''
          ).then((result) {
            _tryExtract(result.toString().replaceAll('"', ''));
          });
        },
      ))
      ..loadRequest(Uri.parse(widget.url));

    // timeout بعد 15 ثانية
    Future.delayed(const Duration(seconds: 15), () {
      if (!_done && mounted) widget.onTimeout();
    });
  }

  void _tryExtract(String url) {
    if (_done || url.isEmpty) return;
    final coords = MapLauncherService.extractCoords(url);
    if (coords != null) {
      _done = true;
      widget.onCoordsFound(coords);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                color: Color(0xFFD4A017),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'جارٍ تحديد الموقع...',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF1A1000),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            // WebView مخفي
            SizedBox(
              width: 1,
              height: 1,
              child: WebViewWidget(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _MapPickerSheet extends StatelessWidget {
  final List<AvailableMap> availableMaps;
  final Map<String, double>? coords;
  final String rawUrl;
  final bool isDark;

  const _MapPickerSheet({
    required this.availableMaps,
    required this.coords,
    required this.rawUrl,
    required this.isDark,
  });

  static const gold = Color(0xFFD4A017);

  Future<void> _launch(AvailableMap map) async {
    final lat = coords?['lat'];
    final lng = coords?['lng'];
    final name = map.mapName.toLowerCase();

    if (lat != null && lng != null) {
      await _openWithDeepLink(name, lat, lng);
      return;
    }

    // فتح الرابط الأصلي كـ fallback
    final uri = Uri.tryParse(rawUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openWithDeepLink(String name, double lat, double lng) async {
    final Map<String, String> deepLinks = {
      'waze':   'waze://?ll=$lat,$lng&navigate=yes',
      'apple':  'maps://?ll=$lat,$lng&q=الموقع',
      'here':   'here-location://$lat,$lng?q=الموقع',
      'yandex': 'yandexmaps://maps.yandex.com/?pt=$lng,$lat&z=16',
      'osmand': 'osmand.geo://$lat,$lng',
      'sygic':  'com.sygic.aura://coordinate|$lng|$lat|drive',
      'google': 'comgooglemaps://?q=$lat,$lng&zoom=15',
    };

    for (final entry in deepLinks.entries) {
      if (name.contains(entry.key)) {
        final uri = Uri.parse(entry.value);
        try {
          // على Android، canLaunchUrl قد يرجع false للـ custom schemes
          // حتى لو التطبيق مثبت — لذا نحاول مباشرة بدون الاعتماد عليها
          final canLaunch = await canLaunchUrl(uri);
          if (canLaunch) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            return;
          }
          // fallback: حاول مباشرة بدون canLaunchUrl
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        } catch (_) {
          // إذا فشل الـ deep link، اكمل للـ geo fallback
          break;
        }
      }
    }

    // geo: URI كـ fallback عام — يعمل مع معظم تطبيقات الخرائط
    try {
      final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
      await launchUrl(geoUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // آخر محاولة: Google Maps عبر HTTPS
      final webUri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1C1C1C) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1000);
    final subColor = isDark ? Colors.white54 : Colors.black45;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFD86B), Color(0xFFD4A017)],
                    ),
                  ),
                  child: const Icon(Icons.map_rounded,
                      color: Colors.black, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('فتح في',
                        style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    Text('اختر تطبيق الخرائط',
                        style: TextStyle(color: subColor, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Divider(
              color: isDark ? Colors.white12 : const Color(0xFFEEE8DA),
              height: 1),
          ...availableMaps.map((map) => InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _launch(map);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          map.icon,
                          width: 42,
                          height: 42,
                          errorBuilder: (_, __, ___) => Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: gold.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child:
                                const Icon(Icons.map_rounded, color: gold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          map.mapName,
                          style: TextStyle(
                              color: textColor,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded,
                          size: 14, color: subColor),
                    ],
                  ),
                ),
              )),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}