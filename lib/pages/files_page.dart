import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../widgets/shared_widgets.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  LOCAL CACHE SERVICE
//  Saves & loads the file list from disk so it's instant on re-open.
// ══════════════════════════════════════════════════════════════════════════════
class _CacheService {
  static const _cacheFileName = 'pdf_posts_cache.json';

  static Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_cacheFileName');
  }

  static Future<List<PdfFileItem>> load() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return [];
      final body = await file.readAsString();
      final decoded = jsonDecode(body);
      if (decoded is! List) return [];
      return decoded
          .map((e) => PdfFileItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<PdfFileItem> files) async {
    try {
      final file = await _cacheFile();
      final data = files.map((f) => f.toJson()).toList();
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  FILES PAGE
// ══════════════════════════════════════════════════════════════════════════════
class FilesPage extends StatefulWidget {
  final bool isDark;
  const FilesPage({super.key, required this.isDark});

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> with SingleTickerProviderStateMixin {
  static const gold = Color(0xFFD4A017);

  static const String _apiUrl =
      'https://majidalbana.com/admin/pdf-posts/load_pdf_posts.php';
  static const String _fileBaseUrl = 'https://majidalbana.com/uploads-pdf/';
  static const String _thumbBaseUrl = 'https://majidalbana.com/uploads-pdf/img/';

  final Map<int, double> _downloadProgress = {};
  final Set<int> _downloading = {};
  final Set<int> _downloaded = {};

  List<PdfFileItem> _files = [];
  List<PdfFileItem> _filteredFiles = [];
  bool _loading = true;          // only true on very first launch (no cache)
  bool _backgroundRefreshing = false;
  String? _error;
  Timer? _refreshTimer;

  // Search
  bool _searchActive = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  late final AnimationController _searchAnimCtrl;
  late final Animation<double> _searchAnim;

  @override
  void initState() {
    super.initState();
    _searchAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _searchAnim = CurvedAnimation(parent: _searchAnimCtrl, curve: Curves.easeOutCubic);
    _searchCtrl.addListener(_onSearchChanged);

    _initLoad();
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _fetchFromNetwork(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _searchAnimCtrl.dispose();
    super.dispose();
  }

  // ── Search ────────────────────────────────────────────────────────────────

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    setState(() {
      _filteredFiles = q.isEmpty
          ? List.from(_files)
          : _files.where((f) {
              final lower = q.toLowerCase();
              return f.title.toLowerCase().contains(lower) ||
                  f.description.toLowerCase().contains(lower) ||
                  f.author.toLowerCase().contains(lower) ||
                  f.fileName.toLowerCase().contains(lower);
            }).toList();
    });
  }

  void _openSearch() {
    setState(() => _searchActive = true);
    _searchAnimCtrl.forward();
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    _searchAnimCtrl.reverse().then((_) {
      if (mounted) {
        setState(() {
          _searchActive = false;
          _searchCtrl.clear();
          _filteredFiles = List.from(_files);
        });
      }
    });
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _initLoad() async {
    // 1. Load cache instantly — show it right away
    final cached = await _CacheService.load();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _files = cached;
        _filteredFiles = List.from(cached);
        _loading = false;
      });
    }
    // 2. Then fetch from network (silently if we had cache)
    await _fetchFromNetwork(silent: cached.isNotEmpty);
  }

  Future<void> _fetchFromNetwork({required bool silent}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (silent && mounted) {
      setState(() => _backgroundRefreshing = true);
    }

    try {
      final uri = Uri.parse('$_apiUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      final request = await HttpClient().getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! List) throw Exception('صيغة البيانات غير صحيحة');

      final fresh = decoded
          .map((e) => PdfFileItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      // Check if there's actually anything new before rebuilding
      final hasNewContent = _hasNewItems(fresh);

      if (!mounted) return;

      if (hasNewContent || _files.isEmpty) {
        setState(() {
          // Merge: prepend new items with a "new" animation flag
          _files = fresh;
          _onSearchChanged(); // re-apply search filter
          _loading = false;
          _error = null;
          _backgroundRefreshing = false;
        });
        // Save to cache
        await _CacheService.save(fresh);
      } else {
        if (mounted) setState(() => _backgroundRefreshing = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _backgroundRefreshing = false;
        _loading = false;
        if (_files.isEmpty) {
          _error = 'تعذر تحميل الملفات. تأكد من الاتصال بالإنترنت.';
        }
      });
    }
  }

  bool _hasNewItems(List<PdfFileItem> fresh) {
    if (fresh.length != _files.length) return true;
    final existingIds = _files.map((f) => f.id).toSet();
    return fresh.any((f) => !existingIds.contains(f.id));
  }

  // ── Download ──────────────────────────────────────────────────────────────

  Future<void> _downloadFile(PdfFileItem file) async {
    if (_downloading.contains(file.id)) return;
    setState(() {
      _downloading.add(file.id);
      _downloadProgress[file.id] = 0;
    });

    try {
      final request = await HttpClient().getUrl(Uri.parse(file.fileUrl));
      final response = await request.close();
      if (response.statusCode != 200) throw Exception('فشل التحميل');

      final dir = await getApplicationDocumentsDirectory();
      final output = File('${dir.path}/${file.safeFileName}').openWrite();
      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      await for (final chunk in response) {
        receivedBytes += chunk.length;
        output.add(chunk);
        if (totalBytes > 0 && mounted) {
          setState(() => _downloadProgress[file.id] = receivedBytes / totalBytes);
        }
      }

      await output.flush();
      await output.close();

      if (!mounted) return;
      setState(() {
        _downloading.remove(file.id);
        _downloadProgress.remove(file.id);
        _downloaded.add(file.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تحميل الملف: ${file.title}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFD4A017),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _downloading.remove(file.id);
        _downloadProgress.remove(file.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فشل تحميل الملف. الإنترنت قرر يأخذ استراحة.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openFile(PdfFileItem file) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PdfBrowserPage(file: file, isDark: widget.isDark),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pageBg = widget.isDark ? const Color(0xFF050505) : const Color(0xFFF8F6F0);
    final displayList = _searchActive ? _filteredFiles : _files;

    return Container(
      color: pageBg,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── App Bar ──────────────────────────────────────────────────────
          PremiumAppBar(
  title: 'الملفات',
  isDark: widget.isDark,
),

          // ── Search bar (animated) ─────────────────────────────────────
          SliverToBoxAdapter(
            child: AnimatedBuilder(
              animation: _searchAnim,
              builder: (_, __) {
                if (!_searchActive && _searchAnim.value == 0) {
                  return const SizedBox.shrink();
                }
                return SizeTransition(
                  sizeFactor: _searchAnim,
                  child: FadeTransition(
                    opacity: _searchAnim,
                    child: _buildSearchBar(),
                  ),
                );
              },
            ),
          ),

          // ── New post indicator ────────────────────────────────────────
          if (_backgroundRefreshing)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: gold.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '    ',
                      style: TextStyle(
                        color: gold.withOpacity(0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Content ───────────────────────────────────────────────────
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator(color: gold)),
            )
          else if (_error != null && _files.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _ErrorState(
                message: _error!,
                isDark: widget.isDark,
                onRetry: () => _fetchFromNetwork(silent: false),
              ),
            )
          else if (displayList.isEmpty && _searchActive)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _SearchEmptyState(query: _searchCtrl.text, isDark: widget.isDark),
            )
          else if (displayList.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(isDark: widget.isDark),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 105),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final file = displayList[i];
                    return _FileCard(
                      key: ValueKey(file.id),
                      file: file,
                      isDark: widget.isDark,
                      isDownloading: _downloading.contains(file.id),
                      isDownloaded: _downloaded.contains(file.id),
                      progress: _downloadProgress[file.id] ?? 0,
                      searchQuery: _searchActive ? _searchCtrl.text : '',
                      onDownload: () => _downloadFile(file),
                      onView: () => _openFile(file),
                    );
                  },
                  childCount: displayList.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAppBar(Color pageBg) {
    return SliverToBoxAdapter(
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          PremiumAppBar(title: 'الملفات', isDark: widget.isDark),
          Positioned(
            left: 16,
            child: GestureDetector(
              onTap: _searchActive ? _closeSearch : _openSearch,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _searchActive
                      ? const Color(0xFFD4A017).withOpacity(0.18)
                      : const Color(0xFFD4A017).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFD4A017).withOpacity(_searchActive ? 0.5 : 0.22),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    _searchActive ? Icons.close_rounded : Icons.search_rounded,
                    key: ValueKey(_searchActive),
                    color: const Color(0xFFD4A017),
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final cardBg = widget.isDark ? const Color(0xFF111111) : Colors.white;
    final hintColor = widget.isDark ? Colors.white38 : Colors.black38;
    final textColor = widget.isDark ? Colors.white : const Color(0xFF17120A);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.35)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4A017).withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(widget.isDark ? 0.3 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            const SizedBox(width: 14),
            Icon(Icons.search_rounded, color: const Color(0xFFD4A017), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  hintText: 'ابحث في الملفات...',
                  hintStyle: TextStyle(
                    color: hintColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_searchCtrl.text.isNotEmpty) ...[
              GestureDetector(
                onTap: () {
                  _searchCtrl.clear();
                  _searchFocus.requestFocus();
                },
                child: Container(
                  margin: const EdgeInsets.only(left: 10),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: hintColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close_rounded, size: 14, color: hintColor),
                ),
              ),
            ],
            const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DATA MODEL
// ══════════════════════════════════════════════════════════════════════════════
class PdfFileItem {
  final int id;
  final String title;
  final String description;
  final String fileName;
  final String fileSize;
  final String author;
  final String thumbnail;
  final String createdAt;

  const PdfFileItem({
    required this.id,
    required this.title,
    required this.description,
    required this.fileName,
    required this.fileSize,
    required this.author,
    required this.thumbnail,
    required this.createdAt,
  });

  factory PdfFileItem.fromJson(Map<String, dynamic> json) {
    return PdfFileItem(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      title: _clean(json['title']),
      description: _clean(json['description']),
      fileName: _clean(json['file_name']),
      fileSize: _clean(json['file_size']),
      author: _clean(json['author']).isEmpty ? 'د.ماجد البنا' : _clean(json['author']),
      thumbnail: _clean(json['thumbnail']),
      createdAt: _clean(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'file_name': fileName,
        'file_size': fileSize,
        'author': author,
        'thumbnail': thumbnail,
        'created_at': createdAt,
      };

  static String _clean(dynamic value) => '${value ?? ''}'.trim();

  String get fileUrl => '${_FilesPageState._fileBaseUrl}$fileName';
  String get thumbnailUrl => '${_FilesPageState._thumbBaseUrl}$thumbnail';

  String get safeFileName {
    if (fileName.isNotEmpty) return fileName;
    final safeTitle = title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return '$safeTitle.pdf';
  }

  String get extension {
    final parts = fileName.split('.');
    if (parts.length < 2) return 'PDF';
    return parts.last.toUpperCase();
  }

  bool get hasThumbnail => thumbnail.isNotEmpty;

  String get displayDate {
    if (createdAt.isEmpty) return '';
    final raw = createdAt.split(' ').first;
    if (raw.contains('-')) return raw;
    return createdAt;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  FILE CARD  (with search highlight)
// ══════════════════════════════════════════════════════════════════════════════
class _FileCard extends StatelessWidget {
  final PdfFileItem file;
  final bool isDark;
  final bool isDownloading;
  final bool isDownloaded;
  final double progress;
  final String searchQuery;
  final VoidCallback onDownload;
  final VoidCallback onView;

  const _FileCard({
    super.key,
    required this.file,
    required this.isDark,
    required this.isDownloading,
    required this.isDownloaded,
    required this.progress,
    required this.searchQuery,
    required this.onDownload,
    required this.onView,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF111111) : Colors.white;
    final textPrimary = isDark ? const Color(0xFFE9E9E9) : const Color(0xFF17120A);
    final textSub = isDark ? Colors.white60 : Colors.black54;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeroThumbnail(file: file, isDark: isDark),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title with search highlight
                  _HighlightText(
                    text: file.title.isEmpty ? 'ملف بدون عنوان' : file.title,
                    query: searchQuery,
                    maxLines: 2,
                    textAlign: TextAlign.right,
                    baseStyle: TextStyle(
                      color: textPrimary,
                      fontSize: 18,
                      height: 1.45,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      const _AuthorAvatar(),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _HighlightText(
                              text: file.author,
                              query: searchQuery,
                              maxLines: 1,
                              textAlign: TextAlign.start,
                              baseStyle: const TextStyle(
                                color: Color(0xFF486CFF),
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (file.displayDate.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                file.displayDate,
                                style: TextStyle(
                                  color: textSub,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: isDark ? Colors.white24 : Colors.black12, height: 1),
                  const SizedBox(height: 18),
                  _FileInfoPill(file: file, isDark: isDark, searchQuery: searchQuery),
                  if (file.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _HighlightText(
                      text: file.description,
                      query: searchQuery,
                      maxLines: 3,
                      textAlign: TextAlign.right,
                      baseStyle: TextStyle(
                        color: textSub,
                        fontSize: 13.5,
                        height: 1.65,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.visibility_rounded,
                          label: 'عرض الملف',
                          isDark: isDark,
                          onPressed: onView,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DownloadButton(
                          isDark: isDark,
                          isDownloading: isDownloading,
                          isDownloaded: isDownloaded,
                          progress: progress,
                          onPressed: onDownload,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  HIGHLIGHT TEXT WIDGET  (highlights search query in yellow)
// ══════════════════════════════════════════════════════════════════════════════
class _HighlightText extends StatelessWidget {
  final String text;
  final String query;
  final int maxLines;
  final TextAlign textAlign;
  final TextStyle baseStyle;

  const _HighlightText({
    required this.text,
    required this.query,
    required this.maxLines,
    required this.textAlign,
    required this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: baseStyle,
      );
    }

    final lower = text.toLowerCase();
    final queryLower = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final idx = lower.indexOf(queryLower, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: baseStyle.copyWith(
          backgroundColor: const Color(0xFFD4A017).withOpacity(0.30),
          color: const Color(0xFFD4A017),
          fontWeight: FontWeight.w900,
        ),
      ));
      start = idx + query.length;
    }

    return Text.rich(
      TextSpan(children: spans, style: baseStyle),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  HERO THUMBNAIL  (cached network image)
// ══════════════════════════════════════════════════════════════════════════════
class _HeroThumbnail extends StatelessWidget {
  final PdfFileItem file;
  final bool isDark;

  const _HeroThumbnail({required this.file, required this.isDark});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1A1710) : const Color(0xFFF1E7CF);

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: bg),
          if (file.hasThumbnail)
            Image.network(
              file.thumbnailUrl,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              // Flutter's Image.network caches images in memory automatically.
              // For disk-level cache, add the `cached_network_image` package.
              errorBuilder: (_, __, ___) =>
                  _FallbackThumbnail(extension: file.extension, isDark: isDark),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: bg),
                    Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: gold,
                        value: progress.expectedTotalBytes == null
                            ? null
                            : progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!,
                      ),
                    ),
                  ],
                );
              },
            )
          else
            _FallbackThumbnail(extension: file.extension, isDark: isDark),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.10),
                  const Color(0xFFD4A017).withOpacity(0.55),
                ],
              ),
            ),
          ),
          Positioned(
            right: 18,
            bottom: 16,
            child: Container(
              width: 54,
              height: 62,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 0,
                    right: 0,
                    child: CustomPaint(
                      size: const Size(18, 18),
                      painter: _FoldPainter(),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE94343),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        file.extension,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
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

// ══════════════════════════════════════════════════════════════════════════════
//  AUTHOR AVATAR
// ══════════════════════════════════════════════════════════════════════════════
class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFD4A017), Color(0xFFB8860B)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/majid.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.white,
            child: const Icon(Icons.person_rounded, color: Color(0xFFD4A017), size: 30),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  FILE INFO PILL
// ══════════════════════════════════════════════════════════════════════════════
class _FileInfoPill extends StatelessWidget {
  final PdfFileItem file;
  final bool isDark;
  final String searchQuery;

  const _FileInfoPill({
    required this.file,
    required this.isDark,
    required this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1A10) : const Color(0xFFFDF8EC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.22)),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFD4A017).withOpacity(0.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              file.fileSize.isEmpty ? 'PDF' : file.fileSize,
              style: const TextStyle(
                color: Color(0xFFD4A017),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _HighlightText(
              text: file.fileName.isEmpty ? 'ملف PDF' : file.fileName,
              query: searchQuery,
              maxLines: 1,
              textAlign: TextAlign.start,
              baseStyle: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF172033),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Icon(
            Icons.attach_file_rounded,
            size: 18,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ACTION BUTTON  (View)
// ══════════════════════════════════════════════════════════════════════════════
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: isDark ? const Color(0xFF1C1A10) : const Color(0xFFFDF8EC),
          foregroundColor: isDark ? const Color(0xFFE8D2B0) : const Color(0xFF49351B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: const Color(0xFFD4A017).withOpacity(0.35)),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DOWNLOAD BUTTON
// ══════════════════════════════════════════════════════════════════════════════
class _DownloadButton extends StatelessWidget {
  final bool isDark;
  final bool isDownloading;
  final bool isDownloaded;
  final double progress;
  final VoidCallback onPressed;

  const _DownloadButton({
    required this.isDark,
    required this.isDownloading,
    required this.isDownloaded,
    required this.progress,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).clamp(0, 100).round();

    return SizedBox(
      height: 46,
      child: ElevatedButton(
        onPressed: isDownloading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: isDark ? const Color(0xFF1C1A10) : const Color(0xFFFDF8EC),
          disabledBackgroundColor:
              isDark ? const Color(0xFF1C1A10) : const Color(0xFFFDF8EC),
          foregroundColor: isDark ? const Color(0xFFE8D2B0) : const Color(0xFF49351B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: const Color(0xFFD4A017).withOpacity(0.35)),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isDownloading)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress <= 0 ? null : progress,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      const Color(0xFFD4A017).withOpacity(0.25),
                    ),
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isDownloaded
                      ? Icons.check_circle_rounded
                      : isDownloading
                          ? Icons.downloading_rounded
                          : Icons.download_rounded,
                  size: 20,
                ),
                const SizedBox(width: 7),
                Text(
                  isDownloading
                      ? '$percent%'
                      : isDownloaded
                          ? 'تم التحميل'
                          : 'تحميل',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  PDF BROWSER PAGE
// ══════════════════════════════════════════════════════════════════════════════
class _PdfBrowserPage extends StatefulWidget {
  final PdfFileItem file;
  final bool isDark;

  const _PdfBrowserPage({required this.file, required this.isDark});

  @override
  State<_PdfBrowserPage> createState() => _PdfBrowserPageState();
}

class _PdfBrowserPageState extends State<_PdfBrowserPage> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  void _loadPdf() {
    final bgColor = widget.isDark ? '#050505' : '#F8F6F0';
    final pdfUrl = widget.file.fileUrl;

    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes">
  <title>${widget.file.title}</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 100%; height: 100%; background: $bgColor; overflow: hidden; }
    iframe { width: 100%; height: 100%; border: none; display: block; }
  </style>
</head>
<body>
  <iframe
    src="https://mozilla.github.io/pdf.js/web/viewer.html?file=${Uri.encodeComponent(pdfUrl)}"
    allowfullscreen webkitallowfullscreen>
  </iframe>
</body>
</html>
''';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(
          widget.isDark ? const Color(0xFF050505) : const Color(0xFFF8F6F0))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) => setState(() => _progress = value),
          onPageStarted: (_) => setState(() => _hasError = false),
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? false) {
              setState(() => _hasError = true);
            }
          },
        ),
      )
      ..loadHtmlString(html, baseUrl: 'https://majidalbana.com');
  }

  void _retryLoad() {
    setState(() {
      _hasError = false;
      _progress = 0;
    });
    _loadPdf();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? const Color(0xFF050505) : const Color(0xFFF8F6F0);
    final card = widget.isDark ? const Color(0xFF111111) : Colors.white;
    final text = widget.isDark ? Colors.white : const Color(0xFF17120A);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Column(
            children: [
              // ── Top Bar ─────────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFFD4A017).withOpacity(0.22)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withOpacity(widget.isDark ? 0.30 : 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4A017).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Color(0xFFD4A017),
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const _SmallLogo(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'عرض الملف',
                            style: TextStyle(
                              color: const Color(0xFFD4A017).withOpacity(0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            widget.file.title.isEmpty
                                ? widget.file.fileName
                                : widget.file.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: text,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ── Progress ─────────────────────────────────────────────────
              if (_progress < 100 && !_hasError) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progress <= 0 ? null : _progress / 100,
                      color: const Color(0xFFD4A017),
                      backgroundColor:
                          const Color(0xFFD4A017).withOpacity(0.12),
                      minHeight: 3,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              // ── Viewer ────────────────────────────────────────────────────
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: const Color(0xFFD4A017)
                          .withOpacity(widget.isDark ? 0.12 : 0.10),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withOpacity(widget.isDark ? 0.30 : 0.06),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: _hasError
                      ? _ViewerError(
                          isDark: widget.isDark,
                          onRetry: _retryLoad,
                        )
                      : WebViewWidget(controller: _controller),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SMALL LOGO
// ══════════════════════════════════════════════════════════════════════════════
class _SmallLogo extends StatelessWidget {
  const _SmallLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [Color(0xFFD4A017), Color(0xFFB8860B)]),
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/majid.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.white,
            child: const Icon(Icons.menu_book_rounded,
                color: Color(0xFFD4A017), size: 24),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  VIEWER ERROR
// ══════════════════════════════════════════════════════════════════════════════
class _ViewerError extends StatelessWidget {
  final bool isDark;
  final VoidCallback onRetry;
  const _ViewerError({required this.isDark, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final color = isDark ? Colors.white70 : Colors.black54;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_rounded, size: 52, color: color),
            const SizedBox(height: 12),
            Text(
              'تعذر عرض الملف داخل المتصفح.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4A017),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  FALLBACK THUMBNAIL
// ══════════════════════════════════════════════════════════════════════════════
class _FallbackThumbnail extends StatelessWidget {
  final String extension;
  final bool isDark;

  const _FallbackThumbnail({required this.extension, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? const Color(0xFF151515) : const Color(0xFFF0ECE2),
      child: Center(
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: const Color(0xFFD4A017).withOpacity(0.12),
            borderRadius: BorderRadius.circular(24),
            border:
                Border.all(color: const Color(0xFFD4A017).withOpacity(0.25)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.picture_as_pdf_rounded,
                  color: Color(0xFFD4A017), size: 36),
              const SizedBox(height: 6),
              Text(
                extension,
                style: const TextStyle(
                  color: Color(0xFFD4A017),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  FOLD PAINTER
// ══════════════════════════════════════════════════════════════════════════════
class _FoldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFEAEAEA);
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════════════
//  SEARCH EMPTY STATE
// ══════════════════════════════════════════════════════════════════════════════
class _SearchEmptyState extends StatelessWidget {
  final String query;
  final bool isDark;
  const _SearchEmptyState({required this.query, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = isDark ? Colors.white70 : Colors.black54;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFD4A017).withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.search_off_rounded,
                  color: Color(0xFFD4A017), size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد نتائج لـ "$query"',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF17120A),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'جرّب كلمة بحث مختلفة',
              style: TextStyle(color: color, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ERROR STATE
// ══════════════════════════════════════════════════════════════════════════════
class _ErrorState extends StatelessWidget {
  final String message;
  final bool isDark;
  final VoidCallback onRetry;

  const _ErrorState(
      {required this.message, required this.isDark, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final color = isDark ? Colors.white70 : Colors.black54;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, color: color, size: 46),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4A017),
              foregroundColor: Colors.black,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  EMPTY STATE
// ══════════════════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final bool isDark;
  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = isDark ? Colors.white70 : Colors.black54;
    return Center(
      child: Text(
        'لا توجد ملفات حالياً',
        style:
            TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }
}