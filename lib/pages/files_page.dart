import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/shared_widgets.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
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
bool _isSupervisor() {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email?.trim().toLowerCase();
    return email == 'hmode.qq@gmail.com' || email == 'hmode.qu@gmail.com';
  }

  void _onFilePublished() {
    _fetchFromNetwork(silent: true);
  }

  void _onFileEdited(PdfFileItem updated) {
    setState(() {
      final idx = _files.indexWhere((f) => f.id == updated.id);
      if (idx != -1) _files[idx] = updated;
      _onSearchChanged();
    });
    _CacheService.save(_files);
  }
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
        keyboardDismissBehavior:
    ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── App Bar ──────────────────────────────────────────────────────
          PremiumAppBar(
            title: 'الملفات',
            isDark: widget.isDark,
            onSearchTap: _searchActive ? _closeSearch : _openSearch,
            searchActive: _searchActive,
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
                    final supervisor = _isSupervisor();
                    // First item = publish box for supervisors
                    if (supervisor && i == 0) {
                      return _AdminPdfPublishBox(
                        isDark: widget.isDark,
                        onPublished: _onFilePublished,
                      );
                    }
                    final fileIndex = supervisor ? i - 1 : i;
                    final file = displayList[fileIndex];
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
                      isSupervisor: supervisor,
                      onEdited: _onFileEdited,
                    );
                  },
                  childCount: displayList.length + (_isSupervisor() ? 1 : 0),
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
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
  PdfFileItem copyWith({String? title, String? description}) {
    return PdfFileItem(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      fileName: fileName,
      fileSize: fileSize,
      author: author,
      thumbnail: thumbnail,
      createdAt: createdAt,
    );
  }

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
  final bool isSupervisor;
  final void Function(PdfFileItem) onEdited;

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
    required this.isSupervisor,
    required this.onEdited,
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
                  Row(
                    textDirection: TextDirection.rtl,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _HighlightText(
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
                      ),
                      if (isSupervisor) ...[
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => _EditPdfSheet(
                              file: file,
                              isDark: isDark,
                              onSaved: onEdited,
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: gold.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: gold.withOpacity(0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit_rounded, size: 13, color: gold),
                                const SizedBox(width: 5),
                                Text('تعديل',
                                    style: TextStyle(
                                        color: gold,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
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
                  Divider(color: isDark ? Colors.white24 : const Color.fromARGB(31, 216, 21, 21), height: 1),
                  const SizedBox(height: 18),
                  _FileInfoPill(file: file, isDark: isDark, searchQuery: searchQuery),
                  if (file.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _ExpandableDescription(
                      text: file.description,
                      query: searchQuery,
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
class _ExpandableDescription extends StatefulWidget {
  final String text;
  final String query;
  final TextStyle baseStyle;

  const _ExpandableDescription({
    required this.text,
    required this.query,
    required this.baseStyle,
  });

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}


class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  bool _expanded = false;
  static const gold = Color(0xFFD4A017);
  static const int _collapsedCharLimit = 200; // الحد الذي بعده تظهر "اقرأ المزيد"

  late TapGestureRecognizer _tapRecognizer;

  @override
  void initState() {
    super.initState();
    _tapRecognizer = TapGestureRecognizer()
      ..onTap = () => setState(() => _expanded = !_expanded);
  }

  @override
  void dispose() {
    _tapRecognizer.dispose();
    super.dispose();
  }

  List<TextSpan> _buildSpans(String text) {
    final style = widget.baseStyle;
    if (widget.query.isEmpty) return [TextSpan(text: text)];

    final lower = text.toLowerCase();
    final queryLower = widget.query.toLowerCase();
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
        text: text.substring(idx, idx + widget.query.length),
        style: style.copyWith(
          backgroundColor: const Color(0xFFD4A017).withOpacity(0.30),
          color: const Color(0xFFD4A017),
          fontWeight: FontWeight.w900,
        ),
      ));
      start = idx + widget.query.length;
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final isLong = widget.text.length > _collapsedCharLimit;
    final displayText = (!_expanded && isLong)
        ? widget.text.substring(0, _collapsedCharLimit).trimRight()
        : widget.text;

    final spans = _buildSpans(displayText);

    if (isLong) {
      spans.add(TextSpan(
        text: _expanded ? '  عرض أقل' : '... اقرأ المزيد',
        style: widget.baseStyle.copyWith(
          color: gold,
          fontWeight: FontWeight.w800,
        ),
        recognizer: _tapRecognizer,
      ));
    }

    return Text.rich(
      TextSpan(children: spans, style: widget.baseStyle),
      textAlign: TextAlign.right,
      maxLines: _expanded ? null : 3,
      overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
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
                borderRadius: BorderRadius.circular(8),
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
                color: isDark ? const Color.fromARGB(213, 235, 172, 0) : const Color.fromARGB(255, 190, 143, 54),
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
        label: Text(
  label,
  style: const TextStyle(
    fontFamily: 'Cairo', 
    fontWeight: FontWeight.w900,
  ),
),
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: isDark ? const Color(0xFF1C1A10) : const Color(0xFFFDF8EC),
          foregroundColor: isDark ? const Color(0xFFE8D2B0) : const Color.fromARGB(193, 199, 129, 0),
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
          foregroundColor: isDark ? const Color(0xFFE8D2B0) : const Color.fromARGB(193, 199, 129, 0),
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
class _PdfBrowserPage extends StatefulWidget {
  final PdfFileItem file;
  final bool isDark;

  const _PdfBrowserPage({required this.file, required this.isDark});

  @override
  State<_PdfBrowserPage> createState() => _PdfBrowserPageState();
}
// ══════════════════════════════════════════════════════════════════════════════
//  PDF BROWSER PAGE
// ══════════════════════════════════════════════════════════════════════════════
class _PdfBrowserPageState extends State<_PdfBrowserPage> {
  String? _localPath;
  bool _isLoading = true;
  bool _hasError = false;
  int _totalPages = 0;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    setState(() { _isLoading = true; _hasError = false; });
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/${widget.file.safeFileName}';
      final localFile = File(filePath);

      if (!await localFile.exists()) {
        // تحميل من الإنترنت إذا لم يكن موجوداً محلياً
        final request = await HttpClient().getUrl(Uri.parse(widget.file.fileUrl));
        final response = await request.close();
        if (response.statusCode != 200) throw Exception('فشل التحميل');
        final output = localFile.openWrite();
        await for (final chunk in response) { output.add(chunk); }
        await output.flush();
        await output.close();
      }

      if (!mounted) return;
      setState(() { _localPath = filePath; _isLoading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _isLoading = false; _hasError = true; });
    }
  }

  void _retryLoad() => _loadPdf();

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
                              fontFamily: 'Cairo',
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
                              fontFamily: 'Cairo',
                              color: text,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Download Button ──────────────────────────────────
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          final dir = await getApplicationDocumentsDirectory();
                          final filePath = '${dir.path}/${widget.file.safeFileName}';
                          final localFile = File(filePath);
                          if (await localFile.exists()) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'الملف محفوظ بالفعل على جهازك ✓',
                                    textDirection: TextDirection.rtl,
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  backgroundColor: const Color(0xFF2E7D32),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  margin: const EdgeInsets.all(14),
                                ),
                              );
                            }
                          } else {
                            try {
                              final request = await HttpClient().getUrl(Uri.parse(widget.file.fileUrl));
                              final response = await request.close();
                              if (response.statusCode != 200) throw Exception();
                              final output = localFile.openWrite();
                              await for (final chunk in response) { output.add(chunk); }
                              await output.flush();
                              await output.close();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'تم تحميل الملف بنجاح ✓',
                                      textDirection: TextDirection.rtl,
                                      style: TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    backgroundColor: const Color(0xFFD4A017),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    margin: const EdgeInsets.all(14),
                                  ),
                                );
                              }
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'فشل التحميل. تحقق من الاتصال',
                                      textDirection: TextDirection.rtl,
                                      style: TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    backgroundColor: Colors.red.shade700,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    margin: const EdgeInsets.all(14),
                                  ),
                                );
                              }
                            }
                          }
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4A017).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.download_rounded,
                            color: Color(0xFFD4A017),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Progress ─────────────────────────────────────────────────
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
    ? _ViewerError(isDark: widget.isDark, onRetry: _retryLoad)
    : _isLoading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A017)))
        : PDFView(
            filePath: _localPath!,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: true,
            onRender: (pages) => setState(() => _totalPages = pages ?? 0),
            onPageChanged: (page, _) => setState(() => _currentPage = page ?? 0),
            onError: (_) => setState(() => _hasError = true),
          ),
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
// ══════════════════════════════════════════════════════════════════════════════
//  ADMIN PDF PUBLISH BOX
// ══════════════════════════════════════════════════════════════════════════════
class _AdminPdfPublishBox extends StatefulWidget {
  final bool isDark;
  final VoidCallback onPublished;
  const _AdminPdfPublishBox({required this.isDark, required this.onPublished});
  @override
  State<_AdminPdfPublishBox> createState() => _AdminPdfPublishBoxState();
}

class _AdminPdfPublishBoxState extends State<_AdminPdfPublishBox> {
  static const gold = Color(0xFFD4A017);
  static const _addApi = 'https://majidalbana.com/admin/pdf-posts/add_pdf_post.php';

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  File? _pickedPdf;
  String _pdfName = '';
  bool _publishing = false;
  bool _expanded = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    final picker = ImagePicker();
    // Use file_picker if available; fallback: pick any file via image_picker workaround
    // We use FilePicker from file_picker package here:
    try {
      // ignore: import_of_legacy_library_into_null_safe
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _pickedPdf = File(result.files.single.path!);
          _pdfName = result.files.single.name;
        });
      }
    } catch (_) {
      _showSnack('تعذر فتح منتقي الملفات');
    }
  }

  Future<void> _publish() async {
    if (_titleCtrl.text.trim().isEmpty) { _showSnack('العنوان مطلوب'); return; }
    if (_pickedPdf == null) { _showSnack('الملف PDF مطلوب'); return; }
    setState(() => _publishing = true);
    try {
      final req = http.MultipartRequest('POST', Uri.parse(_addApi));
      req.fields['title'] = _titleCtrl.text.trim();
      req.fields['description'] = _descCtrl.text.trim();
      req.files.add(await http.MultipartFile.fromPath('pdf_file', _pickedPdf!.path));
      final res = await req.send().timeout(const Duration(seconds: 60));
      if (res.statusCode == 200 || res.statusCode == 302) {
        _titleCtrl.clear(); _descCtrl.clear();
        setState(() { _pickedPdf = null; _pdfName = ''; _expanded = false; _publishing = false; });
        _showSnack('تم النشر بنجاح ✓', success: true);
        widget.onPublished();
      } else {
        _showSnack('فشل النشر'); setState(() => _publishing = false);
      }
    } catch (_) { _showSnack('خطأ في الاتصال'); setState(() => _publishing = false); }
  }

  void _showSnack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, textDirection: TextDirection.rtl,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: success ? const Color(0xFF2E7D32) : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(14),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final cardBg = isDark ? const Color(0xFF111111) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF17120A);
    final hintColor = isDark ? Colors.white38 : Colors.black38;
    final fieldBg = isDark ? const Color(0xFF1C1A10) : const Color(0xFFFDF8EC);
    final borderColor = gold.withOpacity(0.35);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: gold.withOpacity(0.4), width: 1.2),
        boxShadow: [BoxShadow(color: gold.withOpacity(isDark ? 0.12 : 0.08), blurRadius: 18, offset: const Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    gold.withOpacity(isDark ? 0.22 : 0.14),
                    gold.withOpacity(isDark ? 0.08 : 0.04),
                  ]),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(color: gold.withOpacity(0.18), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.add_rounded, color: gold, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text('نشر ملف PDF جديد',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(color: textPrimary, fontWeight: FontWeight.w800, fontSize: 15))),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(Icons.keyboard_arrow_down_rounded, color: gold, size: 24),
                    ),
                  ],
                ),
              ),
            ),
            // Body
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title field
                    Container(
                      decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
                      child: TextField(
                        controller: _titleCtrl,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        style: TextStyle(color: textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: 'عنوان الملف *',
                          hintTextDirection: TextDirection.rtl,
                          hintStyle: TextStyle(color: hintColor, fontSize: 13.5),
                          contentPadding: const EdgeInsets.all(14),
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.title_rounded, color: gold.withOpacity(0.6), size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Description field
                    Container(
                      decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
                      child: TextField(
                        controller: _descCtrl,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        maxLines: 4, minLines: 2,
                        style: TextStyle(color: textPrimary, fontSize: 14.5, height: 1.7, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: 'وصف الملف (اختياري)',
                          hintTextDirection: TextDirection.rtl,
                          hintStyle: TextStyle(color: hintColor, fontSize: 13.5),
                          contentPadding: const EdgeInsets.all(14),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // PDF picker
                    GestureDetector(
                      onTap: _pickPdf,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: _pickedPdf != null ? gold.withOpacity(0.08) : fieldBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _pickedPdf != null ? gold.withOpacity(0.6) : borderColor, width: _pickedPdf != null ? 1.5 : 1),
                        ),
                        child: Row(
                          textDirection: TextDirection.rtl,
                          children: [
                            Container(
                              width: 42, height: 42,
                              decoration: BoxDecoration(color: const Color(0xFFE94343).withOpacity(0.12), borderRadius: BorderRadius.circular(11)),
                              child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFE94343), size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_pickedPdf != null ? _pdfName : 'اضغط لاختيار ملف PDF',
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: _pickedPdf != null ? textPrimary : hintColor, fontSize: 13.5, fontWeight: FontWeight.w600)),
                                if (_pickedPdf != null)
                                  Text('تم اختيار الملف ✓',
                                      style: TextStyle(color: gold, fontSize: 11.5, fontWeight: FontWeight.w700)),
                              ],
                            )),
                            Icon(_pickedPdf != null ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                                color: _pickedPdf != null ? gold : hintColor, size: 22),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Publish button
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _publishing ? null : _publish,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: gold, foregroundColor: Colors.white,
                          disabledBackgroundColor: gold.withOpacity(0.5),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _publishing
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                            : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.send_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('نشر الملف', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                              ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  EDIT PDF BOTTOM SHEET
// ══════════════════════════════════════════════════════════════════════════════
class _EditPdfSheet extends StatefulWidget {
  final PdfFileItem file;
  final bool isDark;
  final void Function(PdfFileItem) onSaved;
  const _EditPdfSheet({required this.file, required this.isDark, required this.onSaved});
  @override
  State<_EditPdfSheet> createState() => _EditPdfSheetState();
}

class _EditPdfSheetState extends State<_EditPdfSheet> {
  static const gold = Color(0xFFD4A017);
  static const _updateApi = 'https://majidalbana.com/admin/pdf-posts/update_pdf_post.php';

  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.file.title);
    _descCtrl = TextEditingController(text: widget.file.description);
  }

  @override
  void dispose() { _titleCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) { _showSnack('العنوان مطلوب'); return; }
    setState(() => _saving = true);
    try {
      final res = await http.post(Uri.parse(_updateApi), body: {
        'id': '${widget.file.id}',
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
      }).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final updated = widget.file.copyWith(title: _titleCtrl.text.trim(), description: _descCtrl.text.trim());
        widget.onSaved(updated);
        if (mounted) Navigator.pop(context);
        _showSnack('تم التعديل بنجاح ✓', success: true);
      } else { _showSnack('فشل التعديل'); setState(() => _saving = false); }
    } catch (_) { _showSnack('خطأ في الاتصال'); setState(() => _saving = false); }
  }

  void _showSnack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, textDirection: TextDirection.rtl, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: success ? const Color(0xFF2E7D32) : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(14),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final sheetBg = isDark ? const Color(0xFF111111) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF17120A);
    final hintColor = isDark ? Colors.white38 : Colors.black38;
    final fieldBg = isDark ? const Color(0xFF1C1A10) : const Color(0xFFFDF8EC);
    final borderColor = gold.withOpacity(0.35);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(color: sheetBg, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(color: gold.withOpacity(0.4), borderRadius: BorderRadius.circular(4)),
              )),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: gold.withOpacity(0.15), borderRadius: BorderRadius.circular(11)),
                    child: const Icon(Icons.edit_rounded, color: gold, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text('تعديل الملف', textDirection: TextDirection.rtl,
                      style: TextStyle(color: textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Title field
                  Container(
                    decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
                    child: TextField(
                      controller: _titleCtrl,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: TextStyle(color: textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'عنوان الملف',
                        hintTextDirection: TextDirection.rtl,
                        hintStyle: TextStyle(color: hintColor, fontSize: 13.5),
                        contentPadding: const EdgeInsets.all(14),
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.title_rounded, color: gold.withOpacity(0.6), size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Description field
                  Container(
                    decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
                    child: TextField(
                      controller: _descCtrl,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      maxLines: 5, minLines: 3,
                      style: TextStyle(color: textPrimary, fontSize: 14.5, height: 1.7, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'وصف الملف...',
                        hintTextDirection: TextDirection.rtl,
                        hintStyle: TextStyle(color: hintColor, fontSize: 13.5),
                        contentPadding: const EdgeInsets.all(14),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: gold, foregroundColor: Colors.white,
                        disabledBackgroundColor: gold.withOpacity(0.5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _saving
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.check_rounded, size: 19),
                              SizedBox(width: 8),
                              Text('حفظ التعديلات', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                            ]),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}