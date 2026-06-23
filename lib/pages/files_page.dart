import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/shared_widgets.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import 'package:share_plus/share_plus.dart';

const List<String> kPdfDefaultCategories = [
  'المخططات الأنشائية',
  'الكتب',
  'المدونات العراقية',
  'المدونات الأمريكية',
  'المدونات البريطانية',
  'المدونات الاوربية',
  'المدونات السعودية',
  'المدونات الاماراتية',
  'المدونات المصرية',
  'المدونات السورية',
  'كتب الخرسانة',
  'كتب الأسس',
  'كتب الجسور',
];

String _normalizePdfCategory(String value) => value.trim();

List<String> _mergePdfCategories([Iterable<String> extra = const []]) {
  final seen = <String>{};
  final list = <String>[];
  for (final raw in [...kPdfDefaultCategories, ...extra]) {
    final v = _normalizePdfCategory(raw);
    if (v.isEmpty || seen.contains(v)) continue;
    seen.add(v);
    list.add(v);
  }
  return list;
}


String _mimeTypeForSharedImage(String value) {
  final v = value.toLowerCase();
  if (v.contains('.png') || v.contains('image/png')) return 'image/png';
  if (v.contains('.webp') || v.contains('image/webp')) return 'image/webp';
  return 'image/jpeg';
}

String _extensionForSharedImage(String value) {
  final mime = _mimeTypeForSharedImage(value);
  if (mime == 'image/png') return 'png';
  if (mime == 'image/webp') return 'webp';
  return 'jpg';
}

Future<XFile?> _prepareShareThumbnail(PdfFileItem file) async {
  if (!file.hasThumbnail) return null;

  try {
    final thumbnailUrl = Uri.encodeFull(file.thumbnailUrl);
    final response = await http
        .get(Uri.parse(thumbnailUrl))
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      return null;
    }

    final contentType = response.headers['content-type'] ?? file.thumbnailUrl;
    final extension = _extensionForSharedImage(contentType);
    final mimeType = _mimeTypeForSharedImage(contentType);
    final dir = await getTemporaryDirectory();
    final localFile = File(
      '${dir.path}/majid_pdf_share_${file.id}_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );

    await localFile.writeAsBytes(response.bodyBytes, flush: true);

    return XFile(
      localFile.path,
      mimeType: mimeType,
      name: 'majid_pdf_thumbnail_${file.id}.$extension',
    );
  } catch (_) {
    return null;
  }
}

Future<void> _sharePdfFileItem({
  required BuildContext shareContext,
  required PdfFileItem file,
}) async {
  final box = shareContext.findRenderObject() as RenderBox?;
  final origin = box == null
      ? const Rect.fromLTWH(0, 0, 1, 1)
      : box.localToGlobal(Offset.zero) & box.size;

  final title = file.title.trim().isEmpty
      ? 'ملف من منصة د.ماجد البنا'
      : file.title.trim();
  final fileLink = Uri.encodeFull(file.fileUrl);
  final shareText = '$title\n\n$fileLink';
  final thumbnail = await _prepareShareThumbnail(file);

  if (thumbnail != null) {
    await Share.shareXFiles(
      [thumbnail],
      text: shareText,
      subject: title,
      sharePositionOrigin: origin,
    );
    return;
  }

  await Share.share(
    shareText,
    subject: title,
    sharePositionOrigin: origin,
  );
}
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
class FilesPageScrollBus {
  static VoidCallback? _goTop;

  static void register(VoidCallback callback) {
    _goTop = callback;
  }

  static void unregister(VoidCallback callback) {
    if (_goTop == callback) {
      _goTop = null;
    }
  }

  static void goTop() {
    _goTop?.call();
  }
}

class FilesPageDeepLinkBus {
  static final ValueNotifier<int?> requestedFileId = ValueNotifier<int?>(null);

  static void openFile(int fileId) {
    requestedFileId.value = null;
    requestedFileId.value = fileId;
  }
}


class FileDirectPage extends StatefulWidget {
  final int fileId;
  final bool isDark;

  const FileDirectPage({
    super.key,
    required this.fileId,
    required this.isDark,
  });

  @override
  State<FileDirectPage> createState() => _FileDirectPageState();
}

class _FileDirectPageState extends State<FileDirectPage> {
  static const String _apiUrl =
      'https://majidalbana.com/admin/pdf-posts/load_pdf_posts.php';

  final Map<int, double> _downloadProgress = {};
  final Set<int> _downloading = {};
  final Set<int> _downloaded = {};
  final ValueNotifier<int> _downloadSignal = ValueNotifier<int>(0);

  late final Future<PdfFileItem?> _futureFile;

  @override
  void initState() {
    super.initState();
    _futureFile = _fetchFile();
  }

  @override
  void dispose() {
    _downloadSignal.dispose();
    super.dispose();
  }

  Future<PdfFileItem?> _fetchFile() async {
    try {
      for (final file in _FilesPageMemory.files) {
        if (file.id == widget.fileId) return file;
      }

      final response = await http.get(Uri.parse(_apiUrl)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) return null;

      for (final item in decoded.whereType<Map>()) {
        final file = PdfFileItem.fromJson(Map<String, dynamic>.from(item));
        if (file.id == widget.fileId) return file;
      }
    } catch (_) {}
    return null;
  }

  void _notifyDownloadUpdate() => _downloadSignal.value++;

  void _openFile(PdfFileItem file) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PdfBrowserPage(file: file, isDark: widget.isDark),
      ),
    );
  }

  Future<void> _shareFile(BuildContext shareContext, PdfFileItem file) async {
    await _sharePdfFileItem(shareContext: shareContext, file: file);
  }

  void _showDownloadSnack({required String message, required bool success}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? const Color(0xFF1B8F4D) : const Color(0xFFB3261E),
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 92),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Text(
          message,
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Future<void> _downloadFile(PdfFileItem file) async {
    if (_downloading.contains(file.id)) return;
    HapticFeedback.lightImpact();
    setState(() {
      _downloading.add(file.id);
      _downloadProgress[file.id] = 0.001;
    });
    _notifyDownloadUpdate();

    IOSink? output;
    try {
      final request = await HttpClient().getUrl(Uri.parse(file.fileUrl));
      final response = await request.close();
      if (response.statusCode != 200) throw Exception('download failed');

      final dir = await getApplicationDocumentsDirectory();
      final localFile = File('${dir.path}/${file.safeFileName}');
      final tempFile = File('${dir.path}/.${file.safeFileName}.download');
      if (await tempFile.exists()) await tempFile.delete();

      output = tempFile.openWrite();
      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      await for (final chunk in response) {
        receivedBytes += chunk.length;
        output.add(chunk);
        if (mounted) {
          final nextProgress = totalBytes > 0
              ? (receivedBytes / totalBytes).clamp(0.001, 0.999).toDouble()
              : 0.001;
          setState(() => _downloadProgress[file.id] = nextProgress);
          _notifyDownloadUpdate();
        }
      }

      await output.flush();
      await output.close();
      output = null;

      if (await localFile.exists()) await localFile.delete();
      await tempFile.rename(localFile.path);

      if (!mounted) return;
      setState(() {
        _downloading.remove(file.id);
        _downloadProgress[file.id] = 1;
        _downloaded.add(file.id);
      });
      _notifyDownloadUpdate();

      _showDownloadSnack(
        message: 'تم تحميل الملف بنجاح: ${file.title.isEmpty ? file.fileName : file.title}',
        success: true,
      );

      Future.delayed(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        setState(() => _downloadProgress.remove(file.id));
        _notifyDownloadUpdate();
      });
    } catch (_) {
      try { await output?.close(); } catch (_) {}
      if (!mounted) return;
      setState(() {
        _downloading.remove(file.id);
        _downloadProgress.remove(file.id);
      });
      _notifyDownloadUpdate();
      _showDownloadSnack(
        message: 'فشل تحميل الملف. الإنترنت قرر يتدلل علينا كالعادة.',
        success: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageBg = widget.isDark ? const Color(0xFF050505) : const Color(0xFFF8F6F0);

    return FutureBuilder<PdfFileItem?>(
      future: _futureFile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: pageBg,
            body: const Center(
              child: CircularProgressIndicator(color: Color(0xFFD4A017)),
            ),
          );
        }

        final file = snapshot.data;
        if (file == null) {
          return Scaffold(
            backgroundColor: pageBg,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(
                color: widget.isDark ? Colors.white : Colors.black87,
              ),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'تعذر فتح الملف المطلوب',
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: widget.isDark ? Colors.white70 : Colors.black54,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        }

        return _PdfFileDetailsPage(
          file: file,
          isDark: widget.isDark,
          downloadSignal: _downloadSignal,
          isDownloading: () => _downloading.contains(file.id),
          isDownloaded: () => _downloaded.contains(file.id),
          progress: () => _downloadProgress[file.id] ?? 0,
          onView: () => _openFile(file),
          onDownload: () => _downloadFile(file),
          onShare: (shareContext) => _shareFile(shareContext, file),
        );
      },
    );
  }
}

class _FilesPageMemory {
  static List<PdfFileItem> files = [];
  static String? selectedCategory;
  static String searchText = '';
  static bool searchActive = false;
  static double scrollOffset = 0;
  static bool didLoadOnce = false;
}

class FilesPage extends StatefulWidget {
  final bool isDark;
  const FilesPage({super.key, required this.isDark});

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const gold = Color(0xFFD4A017);

  @override
  bool get wantKeepAlive => true;

  static const String _apiUrl =
      'https://majidalbana.com/admin/pdf-posts/load_pdf_posts.php';
  static const String _fileBaseUrl = 'https://majidalbana.com/uploads-pdf/';
  static const String _thumbBaseUrl = 'https://majidalbana.com/uploads-pdf/img/';

  final Map<int, double> _downloadProgress = {};
  final Set<int> _downloading = {};
  final Set<int> _downloaded = {};
  final ValueNotifier<int> _downloadSignal = ValueNotifier<int>(0);
  final ScrollController _pageScrollController = ScrollController(
    initialScrollOffset: _FilesPageMemory.scrollOffset,
  );

void _scrollToTopFromNav() {
  if (!_pageScrollController.hasClients) return;

  HapticFeedback.selectionClick();

  _pageScrollController.animateTo(
    0,
    duration: const Duration(milliseconds: 520),
    curve: Curves.easeOutCubic,
  );
}

  List<PdfFileItem> _files = List<PdfFileItem>.from(_FilesPageMemory.files);
  List<PdfFileItem> _filteredFiles = [];
  bool _loading = !_FilesPageMemory.didLoadOnce && _FilesPageMemory.files.isEmpty;
  bool _backgroundRefreshing = false;
  String? _selectedCategory = _FilesPageMemory.selectedCategory;
  String? _error;
  Timer? _refreshTimer;
  bool _refreshInProgress = false;
  final Set<int> _incomingFileIds = {};
  final Set<int> _updatedFileIds = {};
  final Map<int, PdfFileItem> _removingFiles = {};
  final Map<int, int> _removingFileIndexes = {};

  // Search
  bool _searchActive = _FilesPageMemory.searchActive;
  final TextEditingController _searchCtrl = TextEditingController(
    text: _FilesPageMemory.searchText,
  );
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
      if (idx != -1) {
        _files[idx] = updated;
        _updatedFileIds.add(updated.id);
      }
      _applyFilters();
    });
    _savePageMemory();
    _CacheService.save(_files);
    _clearRealtimeMarksLater();
  }

  void _onFileDeleted(PdfFileItem deleted) {
    setState(() {
      final oldIndex = _files.indexWhere((f) => f.id == deleted.id);
      _removingFiles[deleted.id] = deleted;
      _removingFileIndexes[deleted.id] = oldIndex < 0 ? 0 : oldIndex;
      _files.removeWhere((f) => f.id == deleted.id);
      _filteredFiles.removeWhere((f) => f.id == deleted.id);
      _incomingFileIds.remove(deleted.id);
      _updatedFileIds.remove(deleted.id);
      _downloading.remove(deleted.id);
      _downloaded.remove(deleted.id);
      _downloadProgress.remove(deleted.id);
      _applyFilters();
    });
    _savePageMemory();
    unawaited(_CacheService.save(_files));
    _clearRealtimeMarksLater();
  }
  void _rememberScrollOffset() {
    if (!_pageScrollController.hasClients) return;
    _FilesPageMemory.scrollOffset = _pageScrollController.offset;
  }

  void _savePageMemory() {
    _FilesPageMemory.files = List<PdfFileItem>.from(_files);
    _FilesPageMemory.selectedCategory = _selectedCategory;
    _FilesPageMemory.searchText = _searchCtrl.text;
    _FilesPageMemory.searchActive = _searchActive;
    _FilesPageMemory.didLoadOnce = true;

    if (_pageScrollController.hasClients) {
      _FilesPageMemory.scrollOffset = _pageScrollController.offset;
    }
  }

  void _restoreScrollPositionSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageScrollController.hasClients) return;

      final maxScroll = _pageScrollController.position.maxScrollExtent;
      final target = _FilesPageMemory.scrollOffset.clamp(0.0, maxScroll);

      if (target > 0) {
        _pageScrollController.jumpTo(target);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    FilesPageScrollBus.register(_scrollToTopFromNav);
    FilesPageDeepLinkBus.requestedFileId.addListener(_onDeepLinkFileRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onDeepLinkFileRequested());
    _pageScrollController.addListener(_rememberScrollOffset);

    _searchAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _searchAnim = CurvedAnimation(
      parent: _searchAnimCtrl,
      curve: Curves.easeOutCubic,
    );

    if (_searchActive) {
      _searchAnimCtrl.value = 1;
    }

    _searchCtrl.addListener(_onSearchChanged);

    if (_files.isNotEmpty || _FilesPageMemory.didLoadOnce) {
      _applyFilters();
      _loading = false;
      _restoreScrollPositionSoon();
      _fetchFromNetwork(silent: true);
    } else {
      _initLoad();
    }

    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchFromNetwork(silent: true);
    });
  }

  @override
  void dispose() {
    _savePageMemory();
    FilesPageScrollBus.unregister(_scrollToTopFromNav);
    FilesPageDeepLinkBus.requestedFileId.removeListener(_onDeepLinkFileRequested);
    _refreshTimer?.cancel();
    _pageScrollController.removeListener(_rememberScrollOffset);
    _pageScrollController.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _searchAnimCtrl.dispose();
    _downloadSignal.dispose();
    super.dispose();
  }

  // ── Search ────────────────────────────────────────────────────────────────

  void _applyFilters() {
    final q = _searchCtrl.text.trim().toLowerCase();
    final selectedCategory = _selectedCategory;
    _filteredFiles = _files.where((f) {
      final matchesCategory = selectedCategory == null || f.category == selectedCategory;
      if (!matchesCategory) return false;
      if (q.isEmpty) return true;
      return f.title.toLowerCase().contains(q) ||
          f.description.toLowerCase().contains(q) ||
          f.author.toLowerCase().contains(q) ||
          f.fileName.toLowerCase().contains(q) ||
          f.category.toLowerCase().contains(q);
    }).toList();
  }

  void _onSearchChanged() {
    setState(() {
      _applyFilters();
      _savePageMemory();
    });
  }

  void _selectCategory(String? category) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedCategory = category;
      _applyFilters();
      _savePageMemory();
    });
  }

  List<String> get _availableCategories =>
      _mergePdfCategories(_files.map((f) => f.category));

  void _openSearch() {
    setState(() {
      _searchActive = true;
      _savePageMemory();
    });
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
          _applyFilters();
          _savePageMemory();
        });
      }
    });
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _initLoad() async {
    if (_files.isNotEmpty) {
      if (mounted) {
        setState(() {
          _applyFilters();
          _loading = false;
        });
        _savePageMemory();
        _restoreScrollPositionSoon();
      }

      await _fetchFromNetwork(silent: true);
      return;
    }

    final cached = await _CacheService.load();

    if (cached.isNotEmpty && mounted) {
      setState(() {
        _files = cached;
        _applyFilters();
        _loading = false;
      });

      _savePageMemory();
      _restoreScrollPositionSoon();
    }

    await _fetchFromNetwork(silent: cached.isNotEmpty);
  }

  Future<void> _fetchFromNetwork({required bool silent}) async {
    if (_refreshInProgress) return;
    _refreshInProgress = true;

    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
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

      if (!mounted) return;

      final oldFiles = List<PdfFileItem>.from(_files);
      final oldById = {for (final f in oldFiles) f.id: f};
      final freshById = {for (final f in fresh) f.id: f};
      final incomingIds = freshById.keys.where((id) => !oldById.containsKey(id)).toSet();
      final removedIds = oldById.keys.where((id) => !freshById.containsKey(id)).toSet();
      final changedIds = freshById.keys.where((id) {
        final old = oldById[id];
        final next = freshById[id];
        return old != null && next != null && old.toStableSignature() != next.toStableSignature();
      }).toSet();

      final hasChanges = incomingIds.isNotEmpty || removedIds.isNotEmpty || changedIds.isNotEmpty || _files.isEmpty;

      if (hasChanges) {
        setState(() {
          for (final id in removedIds) {
            final old = oldById[id];
            if (old == null) continue;
            _removingFiles[id] = old;
            _removingFileIndexes[id] = oldFiles.indexWhere((f) => f.id == id);
          }
          _incomingFileIds
            ..clear()
            ..addAll(incomingIds);
          _updatedFileIds
            ..clear()
            ..addAll(changedIds);
          _files = fresh;
          _applyFilters();
          _loading = false;
          _error = null;
          _backgroundRefreshing = false;
        });
        _savePageMemory();
        unawaited(_CacheService.save(fresh));
        _restoreScrollPositionSoon();
        _clearRealtimeMarksLater();
      } else if (!silent) {
        setState(() {
          _loading = false;
          _error = null;
          _backgroundRefreshing = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      if (!silent || _files.isEmpty) {
        setState(() {
          _backgroundRefreshing = false;
          _loading = false;
          if (_files.isEmpty) {
            _error = 'تعذر تحميل الملفات. تأكد من الاتصال بالإنترنت.';
          }
        });
      }
    } finally {
      _refreshInProgress = false;
    }
  }

  void _clearRealtimeMarksLater() {
    Future.delayed(const Duration(milliseconds: 950), () {
      if (!mounted) return;
      setState(() {
        _incomingFileIds.clear();
        _updatedFileIds.clear();
      });
    });
    Future.delayed(const Duration(milliseconds: 520), () {
      if (!mounted) return;
      if (_removingFiles.isEmpty) return;
      setState(() {
        _removingFiles.clear();
        _removingFileIndexes.clear();
      });
    });
  }

  bool _matchesCurrentView(PdfFileItem file) {
    final selectedCategory = _selectedCategory;
    if (selectedCategory != null && file.category != selectedCategory) return false;
    final q = _searchActive ? _searchCtrl.text.trim().toLowerCase() : '';
    if (q.isEmpty) return true;
    return file.title.toLowerCase().contains(q) ||
        file.description.toLowerCase().contains(q) ||
        file.author.toLowerCase().contains(q) ||
        file.fileName.toLowerCase().contains(q) ||
        file.category.toLowerCase().contains(q);
  }

  List<PdfFileItem> _displayFilesForCurrentView() {
    final base = (_searchActive || _selectedCategory != null)
        ? List<PdfFileItem>.from(_filteredFiles)
        : List<PdfFileItem>.from(_files);

    final ghosts = _removingFiles.values.where(_matchesCurrentView).toList()
      ..sort((a, b) => (_removingFileIndexes[a.id] ?? 0).compareTo(_removingFileIndexes[b.id] ?? 0));

    for (final ghost in ghosts) {
      if (base.any((f) => f.id == ghost.id)) continue;
      final insertAt = (_removingFileIndexes[ghost.id] ?? base.length).clamp(0, base.length).toInt();
      base.insert(insertAt, ghost);
    }
    return base;
  }

  bool _hasNewItems(List<PdfFileItem> fresh) {
    if (fresh.length != _files.length) return true;
    final existingById = {for (final f in _files) f.id: f};
    return fresh.any((f) => existingById[f.id]?.toJson().toString() != f.toJson().toString());
  }

  void _notifyDownloadUpdate() {
    _downloadSignal.value++;
  }

  void _showDownloadSnack({
    required String message,
    required bool success,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 80),
          padding: EdgeInsets.zero,
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: success
                      ? const [Color(0xFF1F7A45), Color(0xFF0F4D2E)]
                      : const [Color(0xFFB3261E), Color(0xFF6E1511)],
                ),
                border: Border.all(color: Colors.white.withOpacity(0.16)),
                boxShadow: [
                  BoxShadow(
                    color: (success ? const Color(0xFF1F7A45) : Colors.red)
                        .withOpacity(0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      success ? Icons.check_rounded : Icons.wifi_off_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        height: 1.45,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }

  // ── Download ──────────────────────────────────────────────────────────────

  Future<void> _downloadFile(PdfFileItem file) async {
    if (_downloading.contains(file.id)) return;
    HapticFeedback.lightImpact();
    setState(() {
      _downloading.add(file.id);
      _downloadProgress[file.id] = 0.001;
    });
    _notifyDownloadUpdate();

    IOSink? output;
    try {
      final request = await HttpClient().getUrl(Uri.parse(file.fileUrl));
      final response = await request.close();
      if (response.statusCode != 200) throw Exception('فشل التحميل');

      final dir = await getApplicationDocumentsDirectory();
      final localFile = File('${dir.path}/${file.safeFileName}');
      final tempFile = File('${dir.path}/.${file.safeFileName}.download');
      if (await tempFile.exists()) await tempFile.delete();

      output = tempFile.openWrite();
      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      await for (final chunk in response) {
        receivedBytes += chunk.length;
        output.add(chunk);
        if (mounted) {
          final nextProgress = totalBytes > 0
              ? (receivedBytes / totalBytes).clamp(0.001, 0.999).toDouble()
              : 0.001;
          setState(() => _downloadProgress[file.id] = nextProgress);
          _notifyDownloadUpdate();
        }
      }

      await output.flush();
      await output.close();
      output = null;

      if (await localFile.exists()) await localFile.delete();
      await tempFile.rename(localFile.path);

      if (!mounted) return;
      setState(() {
        _downloading.remove(file.id);
        _downloadProgress[file.id] = 1;
        _downloaded.add(file.id);
      });
      _notifyDownloadUpdate();

      _showDownloadSnack(
        message: 'تم تحميل الملف بنجاح: ${file.title.isEmpty ? file.fileName : file.title}',
        success: true,
      );

      Future.delayed(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        setState(() => _downloadProgress.remove(file.id));
        _notifyDownloadUpdate();
      });
    } catch (_) {
      try { await output?.close(); } catch (_) {}
      if (!mounted) return;
      setState(() {
        _downloading.remove(file.id);
        _downloadProgress.remove(file.id);
      });
      _notifyDownloadUpdate();
      _showDownloadSnack(
        message: 'فشل تحميل الملف. الإنترنت قرر يتدلل علينا كالعادة.',
        success: false,
      );
    }
  }


  void _onDeepLinkFileRequested() {
    final fileId = FilesPageDeepLinkBus.requestedFileId.value;
    if (fileId == null || fileId <= 0) return;

    FilesPageDeepLinkBus.requestedFileId.value = null;
    _openFileDetailsFromDeepLink(fileId);
  }

  Future<void> _openFileDetailsFromDeepLink(int fileId) async {
    PdfFileItem? file;
    for (final item in _files) {
      if (item.id == fileId) {
        file = item;
        break;
      }
    }

    if (file == null) {
      await _fetchFromNetwork(silent: true);
      for (final item in _files) {
        if (item.id == fileId) {
          file = item;
          break;
        }
      }
    }

    if (!mounted) return;

    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر فتح الملف المطلوب',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
      return;
    }

    _openFileDetails(file);
  }

  void _openFile(PdfFileItem file) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PdfBrowserPage(file: file, isDark: widget.isDark),
      ),
    );
  }

  Future<void> _shareFile(BuildContext shareContext, PdfFileItem file) async {
    await _sharePdfFileItem(shareContext: shareContext, file: file);
  }

  void _openFileDetails(PdfFileItem file) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, animation, secondaryAnimation) {
          return _PdfFileDetailsPage(
            file: file,
            isDark: widget.isDark,
            downloadSignal: _downloadSignal,
            isDownloading: () => _downloading.contains(file.id),
            isDownloaded: () => _downloaded.contains(file.id),
            progress: () => _downloadProgress[file.id] ?? 0,
            onView: () => _openFile(file),
            onDownload: () => _downloadFile(file),
            onShare: (shareContext) => _shareFile(shareContext, file),
          );
        },
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final pageBg = widget.isDark ? const Color(0xFF050505) : const Color(0xFFF8F6F0);
    final displayList = _displayFilesForCurrentView();

    return Container(
      color: pageBg,
      child: CustomScrollView(
        key: const PageStorageKey<String>('files_page_scroll_view'),
        controller: _pageScrollController,
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
          SliverToBoxAdapter(
            child: _PdfCategorySelector(
              isDark: widget.isDark,
              categories: _availableCategories,
              selectedCategory: _selectedCategory,
              onSelected: _selectCategory,
            ),
          ),
          SliverToBoxAdapter(
            child: _SelectedCategoryBanner(
              isDark: widget.isDark,
              category: _selectedCategory,
              count: displayList.length,
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
          else if (displayList.isEmpty && (_searchActive || _selectedCategory != null))
            SliverFillRemaining(
              hasScrollBody: false,
              child: _SearchEmptyState(query: _selectedCategory ?? _searchCtrl.text, isDark: widget.isDark),
            )
          else if (displayList.isEmpty && !_isSupervisor())
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
                    if (supervisor && _selectedCategory == null && i == 0) {
                      return _AdminPdfPublishBox(
                        isDark: widget.isDark,
                        onPublished: _onFilePublished,
                      );
                    }
                    final fileIndex = supervisor && _selectedCategory == null ? i - 1 : i;
                    final file = displayList[fileIndex];
                    return _RealtimeFileCardShell(
                      key: ValueKey('realtime-file-${file.id}'),
                      isNew: _incomingFileIds.contains(file.id),
                      isUpdated: _updatedFileIds.contains(file.id),
                      isRemoving: _removingFiles.containsKey(file.id),
                      child: _FileCard(
                        key: ValueKey(file.id),
                        file: file,
                        isDark: widget.isDark,
                        isDownloading: _downloading.contains(file.id),
                        isDownloaded: _downloaded.contains(file.id),
                        progress: _downloadProgress[file.id] ?? 0,
                        searchQuery: _searchActive ? _searchCtrl.text : '',
                        onDownload: () => _downloadFile(file),
                        onView: () => _openFile(file),
                        onShare: (shareContext) => _shareFile(shareContext, file),
                        onOpenDetails: () => _openFileDetails(file),
                        isSupervisor: supervisor,
                        onEdited: _onFileEdited,
                        onDeleted: _onFileDeleted,
                      ),
                    );
                  },
                  childCount: displayList.length + (_isSupervisor() && _selectedCategory == null ? 1 : 0),
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
//  PDF CATEGORY UI
// ══════════════════════════════════════════════════════════════════════════════
class _PdfCategorySelector extends StatelessWidget {
  final bool isDark;
  final List<String> categories;
  final String? selectedCategory;
  final void Function(String? category) onSelected;

  const _PdfCategorySelector({
    required this.isDark,
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF17120A);
    final bg = isDark ? const Color(0xFF0D0D0D) : const Color(0xFFFFFBF1);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) {},
      onHorizontalDragUpdate: (_) {},
      onHorizontalDragEnd: (_) {},
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: gold.withOpacity(0.20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.24 : 0.05),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: gold.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.dashboard_customize_rounded,
                    color: gold,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تصنيفات الملفات',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ShaderMask(
              shaderCallback: (Rect bounds) {
                return const LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.06, 0.94, 1.0],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: false,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    const SizedBox(width: 14),
                    _PdfCategoryFilterChip(
                      label: 'الكل',
                      selected: selectedCategory == null,
                      isDark: isDark,
                      onTap: () => onSelected(null),
                    ),
                    const SizedBox(width: 8),
                    ...categories.map(
                      (category) => Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: _PdfCategoryFilterChip(
                          label: category,
                          selected: selectedCategory == category,
                          isDark: isDark,
                          onTap: () => onSelected(category),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
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

class _PdfCategoryFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _PdfCategoryFilterChip({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 180),
      scale: selected ? 1.03 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? gold
                : (isDark ? Colors.white.withOpacity(0.055) : Colors.white),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? gold : gold.withOpacity(0.22),
            ),
            boxShadow: selected
                ? [BoxShadow(color: gold.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 6))]
                : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF6B4B08)),
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedCategoryBanner extends StatelessWidget {
  final bool isDark;
  final String? category;
  final int count;

  const _SelectedCategoryBanner({
    required this.isDark,
    required this.category,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    if (category == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 8),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          const Icon(Icons.filter_alt_rounded, color: Color(0xFFD4A017), size: 18),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'قسم $category  •  $count ملف',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfCategoryBadge extends StatelessWidget {
  final String category;
  final bool isDark;

  const _PdfCategoryBadge({required this.category, required this.isDark});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final label = category.trim().isEmpty ? 'بدون تصنيف' : category.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: gold.withOpacity(isDark ? 0.16 : 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: gold.withOpacity(0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.rtl,
        children: [
          const Icon(Icons.category_rounded, color: gold, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: gold,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfCategoryPicker extends StatelessWidget {
  final bool isDark;
  final String selectedCategory;
  final bool useCustom;
  final TextEditingController customController;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<bool> onCustomModeChanged;

  const _PdfCategoryPicker({
    required this.isDark,
    required this.selectedCategory,
    required this.useCustom,
    required this.customController,
    required this.onCategoryChanged,
    required this.onCustomModeChanged,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF17120A);
    final hintColor = isDark ? Colors.white38 : Colors.black38;
    final fieldBg = isDark ? const Color(0xFF1C1A10) : const Color(0xFFFDF8EC);
    final borderColor = gold.withOpacity(0.35);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(Icons.category_rounded, color: gold.withOpacity(0.75), size: 19),
              const SizedBox(width: 8),
              Text(
                'تصنيف الملف',
                style: TextStyle(color: textPrimary, fontSize: 13.5, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              ...kPdfDefaultCategories.map((category) => _MiniCategoryChoice(
                    label: category,
                    selected: !useCustom && selectedCategory == category,
                    isDark: isDark,
                    onTap: () => onCategoryChanged(category),
                  )),
              _MiniCategoryChoice(
                label: 'إضافة تصنيف جديد',
                selected: useCustom,
                isDark: isDark,
                icon: Icons.add_rounded,
                onTap: () => onCustomModeChanged(true),
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: useCustom
                ? Padding(
                    key: const ValueKey('customCategory'),
                    padding: const EdgeInsets.only(top: 10),
                    child: TextField(
                      controller: customController,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        hintText: 'اكتب اسم التصنيف الجديد',
                        hintTextDirection: TextDirection.rtl,
                        hintStyle: TextStyle(color: hintColor, fontSize: 13),
                        filled: true,
                        fillColor: isDark ? Colors.black.withOpacity(0.20) : Colors.white.withOpacity(0.70),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: gold, width: 1.4),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _MiniCategoryChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final IconData? icon;
  final VoidCallback onTap;

  const _MiniCategoryChoice({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
    this.icon,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? gold.withOpacity(0.18) : (isDark ? Colors.white.withOpacity(0.045) : Colors.white),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? gold : gold.withOpacity(0.20)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.rtl,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? gold : (isDark ? Colors.white60 : Colors.black45)),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? gold : (isDark ? Colors.white70 : Colors.black54),
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
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
  final String category;

  const PdfFileItem({
    required this.id,
    required this.title,
    required this.description,
    required this.fileName,
    required this.fileSize,
    required this.author,
    required this.thumbnail,
    required this.createdAt,
    required this.category,
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
      category: _clean(json['category']),
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
        'category': category,
      };

  String toStableSignature() => jsonEncode(toJson());

  static String _clean(dynamic value) => '${value ?? ''}'.trim();
  PdfFileItem copyWith({String? title, String? description, String? category}) {
    return PdfFileItem(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      fileName: fileName,
      fileSize: fileSize,
      author: author,
      thumbnail: thumbnail,
      createdAt: createdAt,
      category: category ?? this.category,
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
  final void Function(BuildContext shareContext) onShare;
  final VoidCallback onOpenDetails;
  final bool isSupervisor;
  final void Function(PdfFileItem) onEdited;
  final void Function(PdfFileItem) onDeleted;

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
    required this.onShare,
    required this.onOpenDetails,
    required this.isSupervisor,
    required this.onEdited,
    required this.onDeleted,
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onOpenDetails,
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
                              onDeleted: onDeleted,
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
                  const SizedBox(height: 10),
                  _PdfCategoryBadge(category: file.category, isDark: isDark),
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
                      onReadMore: onOpenDetails,
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
                    textDirection: TextDirection.rtl,
                    children: [
                      Builder(
                        builder: (shareContext) {
                          return _CircleShareButton(
                            isDark: isDark,
                            onPressed: () => onShare(shareContext),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.visibility_rounded,
                          label: 'عرض',
                          isDark: isDark,
                          onPressed: onView,
                        ),
                      ),
                      const SizedBox(width: 8),
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
        ),
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════════════════════════
//  REALTIME CARD ANIMATION SHELL
// ══════════════════════════════════════════════════════════════════════════════
class _RealtimeFileCardShell extends StatefulWidget {
  final Widget child;
  final bool isNew;
  final bool isUpdated;
  final bool isRemoving;

  const _RealtimeFileCardShell({
    super.key,
    required this.child,
    required this.isNew,
    required this.isUpdated,
    required this.isRemoving,
  });

  @override
  State<_RealtimeFileCardShell> createState() => _RealtimeFileCardShellState();
}

class _RealtimeFileCardShellState extends State<_RealtimeFileCardShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
      reverseDuration: const Duration(milliseconds: 420),
    );
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);
    _fade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _scale = Tween<double>(begin: 0.94, end: 1).animate(curve);
    _slide = Tween<Offset>(begin: const Offset(0, -0.09), end: Offset.zero).animate(curve);
    if (widget.isRemoving) {
      _controller.value = 1;
      _controller.reverse();
    } else if (widget.isNew || widget.isUpdated) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _RealtimeFileCardShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isRemoving && widget.isRemoving) {
      _controller.reverse();
    } else if ((!oldWidget.isNew && widget.isNew) || (!oldWidget.isUpdated && widget.isUpdated)) {
      _controller.forward(from: 0.68);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highlight = widget.isNew || widget.isUpdated;
    if (!highlight && !widget.isRemoving) return widget.child;
    return SizeTransition(
      sizeFactor: _fade,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: ScaleTransition(
            scale: _scale,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: highlight
                    ? [
                        BoxShadow(
                          color: const Color(0xFFD4A017).withOpacity(0.22),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ]
                    : const [],
              ),
              child: widget.child,
            ),
          ),
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
  final VoidCallback? onReadMore;

  const _ExpandableDescription({
    required this.text,
    required this.query,
    required this.baseStyle,
    this.onReadMore,
  });

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  static const gold = Color(0xFFD4A017);
  static const int _collapsedCharLimit = 200;

  TapGestureRecognizer? _readMoreRecognizer;

  @override
  void initState() {
    super.initState();
    _readMoreRecognizer = TapGestureRecognizer()
      ..onTap = () {
        HapticFeedback.selectionClick();
        widget.onReadMore?.call();
      };
  }

  @override
  void dispose() {
    _readMoreRecognizer?.dispose();
    _readMoreRecognizer = null;
    super.dispose();
  }

  List<TextSpan> _buildSpans(String value) {
    final style = widget.baseStyle;
    final query = widget.query;

    if (query.isEmpty) return [TextSpan(text: value)];

    final lower = value.toLowerCase();
    final queryLower = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final idx = lower.indexOf(queryLower, start);
      if (idx == -1) {
        spans.add(TextSpan(text: value.substring(start)));
        break;
      }

      if (idx > start) {
        spans.add(TextSpan(text: value.substring(start, idx)));
      }

      spans.add(
        TextSpan(
          text: value.substring(idx, idx + query.length),
          style: style.copyWith(
            backgroundColor: const Color(0xFFD4A017).withOpacity(0.30),
            color: const Color(0xFFD4A017),
            fontWeight: FontWeight.w900,
          ),
        ),
      );

      start = idx + query.length;
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final isLong = widget.text.length > _collapsedCharLimit;
    final displayText = isLong
        ? widget.text.substring(0, _collapsedCharLimit).trimRight()
        : widget.text;

    final spans = _buildSpans(displayText);

    if (isLong) {
      spans.add(
        TextSpan(
          text: '... اقرأ المزيد',
          style: widget.baseStyle.copyWith(
            color: gold,
            fontWeight: FontWeight.w900,
          ),
          recognizer: _readMoreRecognizer,
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans, style: widget.baseStyle),
      textAlign: TextAlign.right,
      maxLines: isLong ? 3 : null,
      overflow: isLong ? TextOverflow.ellipsis : TextOverflow.visible,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DISK CACHE FOR POST CARD THUMBNAILS ONLY
//  خفيف على السكرول: مسار الكاش ينحسب مرة، لا يوجد spinner متحرك داخل القائمة،
//  ولا يوجد تنزيل مكرر لنفس الصورة إذا أكثر من كرت طلبها بنفس اللحظة.
// ══════════════════════════════════════════════════════════════════════════════
class _PostThumbnailDiskCache {
  static const _folderName = 'pdf_post_seen_thumbnails';
  static Directory? _cachedDir;
  static int _activeDownloads = 0;
  static const int _maxParallelDownloads = 2;
  static final Map<String, File?> _memory = <String, File?>{};
  static final Map<String, Future<File?>> _inFlight = <String, Future<File?>>{};

  static Future<Directory> _dir() async {
    final existing = _cachedDir;
    if (existing != null) return existing;

    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/$_folderName');
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
    _cachedDir = cacheDir;
    return cacheDir;
  }

  static String _safeName(String key, String url) {
    final ext = Uri.tryParse(url)?.path.split('.').last.toLowerCase() ?? 'jpg';
    final cleanExt = RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext) ? ext : 'jpg';
    final safeKey = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    return '$safeKey.$cleanExt';
  }

  static String _cacheId(String key, String url) => '${key}_$url';

  static File? peekMemory(String key, String url) {
    final id = _cacheId(key, url);
    return _memory[id];
  }

  static Future<File?> get(String key, String url) async {
    final id = _cacheId(key, url);
    if (_memory.containsKey(id)) return _memory[id];

    try {
      final file = File('${(await _dir()).path}/${_safeName(key, url)}');
      if (await file.exists() && await file.length() > 0) {
        _memory[id] = file;
        return file;
      }
    } catch (_) {}

    _memory[id] = null;
    return null;
  }

  static Future<File?> saveFromNetwork(String key, String url) {
    final id = _cacheId(key, url);
    final running = _inFlight[id];
    if (running != null) return running;

    final future = _saveFromNetworkInternal(key, url).whenComplete(() {
      _inFlight.remove(id);
    });
    _inFlight[id] = future;
    return future;
  }

  static Future<File?> _saveFromNetworkInternal(String key, String url) async {
    try {
      final cached = await get(key, url);
      if (cached != null) return cached;

      while (_activeDownloads >= _maxParallelDownloads) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      _activeDownloads++;
      try {
        final uri = Uri.parse(url);
        final request = await HttpClient().getUrl(uri);
        final response = await request.close();
        if (response.statusCode != 200) return null;

        final bytes = await consolidateHttpClientResponseBytes(response);
        if (bytes.isEmpty) return null;

        final file = File('${(await _dir()).path}/${_safeName(key, url)}');
        await file.writeAsBytes(bytes, flush: false);
        _memory[_cacheId(key, url)] = file;
        return file;
      } finally {
        _activeDownloads = (_activeDownloads - 1).clamp(0, _maxParallelDownloads).toInt();
      }
    } catch (_) {
      return null;
    }
  }
}

class _CachedPostThumbnail extends StatefulWidget {
  final String url;
  final String cacheKey;
  final BoxFit fit;
  final Alignment alignment;
  final Color placeholderColor;
  final Widget fallback;

  const _CachedPostThumbnail({
    required this.url,
    required this.cacheKey,
    required this.fit,
    required this.alignment,
    required this.placeholderColor,
    required this.fallback,
  });

  @override
  State<_CachedPostThumbnail> createState() => _CachedPostThumbnailState();
}

class _CachedPostThumbnailState extends State<_CachedPostThumbnail> {
  File? _file;
  bool _failed = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _file = _PostThumbnailDiskCache.peekMemory(widget.cacheKey, widget.url);
    if (_file == null) _load();
  }

  @override
  void didUpdateWidget(covariant _CachedPostThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.cacheKey != widget.cacheKey) {
      _token++;
      _file = _PostThumbnailDiskCache.peekMemory(widget.cacheKey, widget.url);
      _failed = false;
      if (_file == null) _load();
    }
  }

  Future<void> _load() async {
    final token = _token;
    final cached = await _PostThumbnailDiskCache.get(widget.cacheKey, widget.url);
    if (!mounted || token != _token) return;
    if (cached != null) {
      setState(() => _file = cached);
      return;
    }

    final downloaded = await _PostThumbnailDiskCache.saveFromNetwork(widget.cacheKey, widget.url);
    if (!mounted || token != _token) return;
    if (downloaded != null) {
      setState(() => _file = downloaded);
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback;
    final file = _file;
    if (file == null) {
      return Container(color: widget.placeholderColor);
    }

    final mq = MediaQuery.of(context);
    final dpr = mq.devicePixelRatio.clamp(1.0, 3.0);
    final logicalWidth = mq.size.width;
    final cacheWidth = (logicalWidth * dpr).round().clamp(480, 1280).toInt();

    return ColoredBox(
      color: Colors.white,
      child: Image.file(
        file,
        fit: widget.fit,
        alignment: widget.alignment,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        cacheWidth: cacheWidth,
        errorBuilder: (_, __, ___) => widget.fallback,
      ),
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
            _CachedPostThumbnail(
              url: file.thumbnailUrl,
              cacheKey: '${file.id}_${file.thumbnail}',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              placeholderColor: Colors.white,
              fallback: _FallbackThumbnail(extension: file.extension, isDark: isDark),
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


class _CircleShareButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback onPressed;

  const _CircleShareButton({
    required this.isDark,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: ElevatedButton(
        onPressed: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: EdgeInsets.zero,
          backgroundColor:
              isDark ? const Color(0xFF1C1A10) : const Color(0xFFFDF8EC),
          foregroundColor:
              isDark ? const Color(0xFFE8D2B0) : const Color.fromARGB(193, 199, 129, 0),
          shape: CircleBorder(
            side: BorderSide(
              color: const Color(0xFFD4A017).withOpacity(0.35),
            ),
          ),
        ),
        child: const Icon(
          Icons.share_rounded,
          size: 21,
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

class _PdfFileDetailsPage extends StatelessWidget {
  final PdfFileItem file;
  final bool isDark;
  final Listenable downloadSignal;
  final bool Function() isDownloading;
  final bool Function() isDownloaded;
  final double Function() progress;
  final VoidCallback onView;
  final VoidCallback onDownload;
  final void Function(BuildContext shareContext) onShare;

  const _PdfFileDetailsPage({
    required this.file,
    required this.isDark,
    required this.downloadSignal,
    required this.isDownloading,
    required this.isDownloaded,
    required this.progress,
    required this.onView,
    required this.onDownload,
    required this.onShare,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final pageBg = isDark ? const Color(0xFF050505) : const Color(0xFFF8F6F0);
    final surface = isDark ? const Color(0xFF111111) : Colors.white;
    final softSurface = isDark ? const Color(0xFF17130B) : const Color(0xFFFFFBF1);
    final textPrimary = isDark ? const Color(0xFFEDEDED) : const Color(0xFF17120A);
    final textSub = isDark ? Colors.white70 : Colors.black54;
    final title = file.title.isEmpty ? 'ملف بدون عنوان' : file.title;

    return Scaffold(
      backgroundColor: pageBg,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() > 320 && Navigator.of(context).canPop()) {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          }
        },
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
              SliverAppBar(
                pinned: true,
                elevation: 0,
                backgroundColor: pageBg.withOpacity(0.96),
                surfaceTintColor: Colors.transparent,
                automaticallyImplyLeading: false,
                leadingWidth: 64,
                leading: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 12),
                  child: _DetailRoundIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    isDark: isDark,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                title: Text(
                  'تفاصيل الملف',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                centerTitle: true,
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(34),
                          gradient: LinearGradient(
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                            colors: isDark
                                ? const [Color(0xFF181109), Color(0xFF090909)]
                                : const [Color(0xFFFFF8E8), Color(0xFFFFFFFF)],
                          ),
                          border: Border.all(
                            color: gold.withOpacity(isDark ? 0.20 : 0.28),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(isDark ? 0.38 : 0.09),
                              blurRadius: 28,
                              offset: const Offset(0, 16),
                            ),
                            BoxShadow(
                              color: gold.withOpacity(isDark ? 0.08 : 0.12),
                              blurRadius: 34,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(34),
                          child: Stack(
                            children: [
                              Positioned(
                                left: -46,
                                top: -40,
                                child: Container(
                                  width: 170,
                                  height: 170,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: gold.withOpacity(0.10),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: -80,
                                bottom: -85,
                                child: Container(
                                  width: 210,
                                  height: 210,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: gold.withOpacity(0.07),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final wide = constraints.maxWidth >= 620;
                                    final preview = _DetailPreviewPanel(file: file, isDark: isDark);
                                    final info = _DetailHeaderInfo(
                                      file: file,
                                      title: title,
                                      isDark: isDark,
                                      textPrimary: textPrimary,
                                      textSub: textSub,
                                    );

                                    if (wide) {
                                      return Row(
                                        textDirection: TextDirection.rtl,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(width: 230, child: preview),
                                          const SizedBox(width: 18),
                                          Expanded(child: info),
                                        ],
                                      );
                                    }

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        preview,
                                        const SizedBox(height: 18),
                                        info,
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (file.description.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _DetailSectionCard(
                          isDark: isDark,
                          surface: surface,
                          title: 'وصف الملف',
                          icon: Icons.notes_rounded,
                          child: Text(
                            file.description,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: textSub,
                              fontSize: 14.5,
                              height: 1.85,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _DetailSectionCard(
                        isDark: isDark,
                        surface: surface,
                        title: 'معلومات الملف',
                        icon: Icons.inventory_2_rounded,
                        child: Column(
                          children: [
                            _DetailInfoRow(
                              icon: Icons.description_rounded,
                              label: 'اسم الملف',
                              value: file.fileName.isEmpty ? 'ملف ${file.extension}' : file.fileName,
                              isDark: isDark,
                            ),
                            _DetailInfoRow(
                              icon: Icons.sd_storage_rounded,
                              label: 'الحجم',
                              value: file.fileSize.isEmpty ? 'غير محدد' : file.fileSize,
                              isDark: isDark,
                            ),
                            _DetailInfoRow(
                              icon: Icons.category_rounded,
                              label: 'التصنيف',
                              value: file.category.isEmpty ? 'بدون تصنيف' : file.category,
                              isDark: isDark,
                            ),
                            _DetailInfoRow(
                              icon: Icons.calendar_month_rounded,
                              label: 'تاريخ النشر',
                              value: file.displayDate.isEmpty ? 'غير محدد' : file.displayDate,
                              isDark: isDark,
                              showDivider: false,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: softSurface,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: gold.withOpacity(0.22)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(isDark ? 0.22 : 0.06),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Row(
                          textDirection: TextDirection.rtl,
                          children: [
                            Expanded(
                              flex: 5,
                              child: _DetailPrimaryAction(
                                icon: Icons.visibility_rounded,
                                label: 'عرض الملف',
                                subLabel: 'افتحه داخل التطبيق',
                                isDark: isDark,
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  onView();
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 4,
                              child: AnimatedBuilder(
                                animation: downloadSignal,
                                builder: (_, __) => _DetailDownloadAction(
                                  isDark: isDark,
                                  isDownloading: isDownloading(),
                                  isDownloaded: isDownloaded(),
                                  progress: progress(),
                                  onTap: onDownload,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Builder(
                              builder: (shareContext) {
                                return _DetailShareAction(
                                  isDark: isDark,
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    onShare(shareContext);
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _PdfCommentsSection(
                        fileId: file.id,
                        isDark: isDark,
                        surface: surface,
                      ),
                    ],
                  ),
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailHeaderInfo extends StatelessWidget {
  final PdfFileItem file;
  final String title;
  final bool isDark;
  final Color textPrimary;
  final Color textSub;

  const _DetailHeaderInfo({
    required this.file,
    required this.title,
    required this.isDark,
    required this.textPrimary,
    required this.textSub,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(isDark ? 0.08 : 0.86),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: gold.withOpacity(0.30)),
              ),
              child: Text(
                file.extension,
                style: const TextStyle(
                  color: gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 23,
                  height: 1.42,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: _PdfCategoryBadge(category: file.category, isDark: isDark),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.045) : Colors.white.withOpacity(0.72),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              const _AuthorAvatar(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF486CFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      file.displayDate.isEmpty ? 'تاريخ النشر غير محدد' : 'نشر بتاريخ ${file.displayDate}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textSub,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.start,
          children: [
            _DetailMetaChip(
              icon: Icons.insert_drive_file_rounded,
              label: file.extension,
              isDark: isDark,
            ),
            _DetailMetaChip(
              icon: Icons.sd_storage_rounded,
              label: file.fileSize.isEmpty ? 'حجم غير محدد' : file.fileSize,
              isDark: isDark,
            ),
            _DetailMetaChip(
              icon: Icons.category_rounded,
              label: file.category.isEmpty ? 'بدون تصنيف' : file.category,
              isDark: isDark,
            ),
            _DetailMetaChip(
              icon: Icons.calendar_today_rounded,
              label: file.displayDate.isEmpty ? 'بدون تاريخ' : file.displayDate,
              isDark: isDark,
            ),
          ],
        ),
      ],
    );
  }
}

class _DetailPreviewPanel extends StatelessWidget {
  final PdfFileItem file;
  final bool isDark;

  const _DetailPreviewPanel({required this.file, required this.isDark});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF201A10) : const Color(0xFFF6E8C8);

    return AspectRatio(
      aspectRatio: 1.03,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: gold.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.32 : 0.08),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (file.hasThumbnail)
                _CachedPostThumbnail(
                  url: file.thumbnailUrl,
                  cacheKey: '${file.id}_${file.thumbnail}',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  placeholderColor: Colors.white,
                  fallback: _FallbackThumbnail(
                    extension: file.extension,
                    isDark: isDark,
                  ),
                )
              else
                _FallbackThumbnail(extension: file.extension, isDark: isDark),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.02),
                      Colors.black.withOpacity(0.04),
                      Colors.black.withOpacity(0.36),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 14,
                top: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.94),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.14),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFE94343), size: 18),
                      const SizedBox(width: 6),
                      Text(
                        file.extension,
                        style: const TextStyle(
                          color: Color(0xFF17120A),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.7)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: gold.withOpacity(0.16),
                        ),
                        child: const Icon(Icons.file_open_rounded, color: gold, size: 18),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          file.fileName.isEmpty ? 'جاهز للعرض والتحميل' : file.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF17120A),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
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

class _DetailSectionCard extends StatelessWidget {
  final bool isDark;
  final Color surface;
  final String title;
  final IconData icon;
  final Widget child;

  const _DetailSectionCard({
    required this.isDark,
    required this.surface,
    required this.title,
    required this.icon,
    required this.child,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? const Color(0xFFEDEDED) : const Color(0xFF17120A);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.055)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.26 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: gold.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: gold, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DetailInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final bool showDivider;

  const _DetailInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.showDivider = true,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? const Color(0xFFEDEDED) : const Color(0xFF17120A);
    final textSub = isDark ? Colors.white60 : Colors.black45;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: gold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: gold, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: textSub,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.left,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
          ),
      ],
    );
  }
}

class _DetailMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _DetailMetaChip({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.055) : Colors.white.withOpacity(0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: gold.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: gold, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: isDark ? const Color(0xFFEDEDED) : const Color(0xFF17120A),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPrimaryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subLabel;
  final bool isDark;
  final VoidCallback onTap;

  const _DetailPrimaryAction({
    required this.icon,
    required this.label,
    required this.subLabel,
    required this.isDark,
    required this.onTap,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFD4A017), Color(0xFFB8860B)],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: gold.withOpacity(0.28),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.20),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.78),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
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

class _DetailDownloadAction extends StatelessWidget {
  final bool isDark;
  final bool isDownloading;
  final bool isDownloaded;
  final double progress;
  final VoidCallback onTap;

  const _DetailDownloadAction({
    required this.isDark,
    required this.isDownloading,
    required this.isDownloaded,
    required this.progress,
    required this.onTap,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).clamp(0, 100).round();
    final label = isDownloading
        ? '$percent%'
        : isDownloaded
            ? 'تم'
            : 'تحميل';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: isDownloading
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap();
              },
        child: Ink(
          height: 62,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF211B10) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: gold.withOpacity(0.30)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isDownloading)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: LinearProgressIndicator(
                      value: progress <= 0 ? null : progress,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(gold.withOpacity(0.18)),
                    ),
                  ),
                ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isDownloaded
                        ? Icons.check_circle_rounded
                        : isDownloading
                            ? Icons.downloading_rounded
                            : Icons.file_download_rounded,
                    color: gold,
                    size: 21,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: isDark ? const Color(0xFFE8D2B0) : const Color(0xFF9B6808),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailShareAction extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;

  const _DetailShareAction({required this.isDark, required this.onTap});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF211B10) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: gold.withOpacity(0.30)),
          ),
          child: const Icon(Icons.ios_share_rounded, color: gold, size: 23),
        ),
      ),
    );
  }
}

class _DetailRoundIconButton extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  const _DetailRoundIconButton({
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            icon,
            color: isDark ? Colors.white : const Color(0xFF17120A),
            size: 21,
          ),
        ),
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════════════════════════
//  PDF COMMENTS
// ══════════════════════════════════════════════════════════════════════════════
class _PdfFileComment {
  final int id;
  final int fileId;
  final String userName;
  final String userAvatar;
  final String userEmail;
  final String text;
  final String createdAt;

  const _PdfFileComment({
    required this.id,
    required this.fileId,
    required this.userName,
    required this.userAvatar,
    required this.userEmail,
    required this.text,
    required this.createdAt,
  });

  factory _PdfFileComment.fromJson(Map<String, dynamic> json) {
    return _PdfFileComment(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      fileId: int.tryParse('${json['pdf_id'] ?? json['file_id'] ?? 0}') ?? 0,
      userName: '${json['user_name'] ?? ''}'.trim(),
      userAvatar: '${json['user_avatar'] ?? ''}'.trim(),
      userEmail: '${json['user_email'] ?? ''}'.trim(),
      text: '${json['comment_text'] ?? ''}'.trim(),
      createdAt: '${json['created_at'] ?? ''}'.trim(),
    );
  }
}

class _PdfCommentsSection extends StatefulWidget {
  final int fileId;
  final bool isDark;
  final Color surface;

  const _PdfCommentsSection({
    required this.fileId,
    required this.isDark,
    required this.surface,
  });

  @override
  State<_PdfCommentsSection> createState() => _PdfCommentsSectionState();
}

class _PdfCommentsSectionState extends State<_PdfCommentsSection> {
  static const gold = Color(0xFFD4A017);
  static const String _loadUrl = 'https://majidalbana.com/admin/pdf-comments/load_pdf_comments.php';
  static const String _addUrl = 'https://majidalbana.com/admin/pdf-comments/add_pdf_comment.php';
  static const String _editUrl = 'https://majidalbana.com/admin/pdf-comments/edit_pdf_comment.php';
  static const String _deleteUrl = 'https://majidalbana.com/admin/pdf-comments/delete_pdf_comment.php';

  final TextEditingController _commentCtrl = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  final ScrollController _commentsScroll = ScrollController();

  List<_PdfFileComment> _comments = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadComments(initial: true);
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadComments(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _commentCtrl.dispose();
    _commentFocus.dispose();
    _commentsScroll.dispose();
    super.dispose();
  }

  bool get _isSupervisor {
    final email = FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase();
    return email == 'hmode.qq@gmail.com' || email == 'hmode.qu@gmail.com';
  }

  Future<void> _loadComments({bool initial = false, bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = initial;
        _error = null;
      });
    }

    try {
      final uri = Uri.parse('$_loadUrl?pdf_id=${widget.fileId}&t=${DateTime.now().millisecondsSinceEpoch}');
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

      final decoded = jsonDecode(response.body);
      if (decoded is! List) throw Exception('صيغة التعليقات غير صحيحة');

      final fresh = decoded
          .map((e) => _PdfFileComment.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      if (!mounted) return;
      final oldSignature = _comments.map((c) => '${c.id}:${c.text}:${c.createdAt}').join('|');
      final newSignature = fresh.map((c) => '${c.id}:${c.text}:${c.createdAt}').join('|');
      if (oldSignature != newSignature || _loading) {
        setState(() {
          _comments = fresh;
          _loading = false;
          _error = null;
        });
      } else if (_loading) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _loading = false;
          _error = 'تعذر تحميل التعليقات.';
        });
      }
    }
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('سجل دخولك أولاً لأضافة تعليق.', success: false);
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _sending = true);

    try {
      final response = await http.post(
        Uri.parse(_addUrl),
        body: {
          'pdf_id': '${widget.fileId}',
          'user_name': (user.displayName ?? user.email ?? 'مستخدم').trim(),
          'user_avatar': (user.photoURL ?? '').trim(),
          'user_email': (user.email ?? '').trim(),
          'comment_text': text,
        },
      ).timeout(const Duration(seconds: 15));

      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 || decoded['success'] != true) {
        throw Exception(decoded['error'] ?? 'فشل الإرسال');
      }

      _commentCtrl.clear();
      _commentFocus.unfocus();
      await _loadComments(silent: true);
      if (!mounted) return;
      setState(() => _sending = false);
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      _showSnack('فشل إرسال التعليق.', success: false);
    }
  }

  Future<void> _editComment(_PdfFileComment comment) async {
    final controller = TextEditingController(text: comment.text);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottom = MediaQuery.of(context).viewInsets.bottom;
        final bg = widget.isDark ? const Color(0xFF111111) : Colors.white;
        final textColor = widget.isDark ? Colors.white : const Color(0xFF17120A);
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: gold.withOpacity(0.22)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.edit_note_rounded, color: gold),
                      const SizedBox(width: 8),
                      Text(
                        'تعديل التعليق',
                        style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: null,
                    minLines: 2,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(color: textColor, fontWeight: FontWeight.w700, height: 1.5),
                    decoration: InputDecoration(
                      hintText: 'اكتب التعديل هنا...',
                      filled: true,
                      fillColor: widget.isDark ? const Color(0xFF171717) : const Color(0xFFF8F6F0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: gold.withOpacity(0.24)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: gold.withOpacity(0.18)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: gold.withOpacity(0.55)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, controller.text.trim()),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('حفظ التعديل'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gold,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    controller.dispose();

    final newText = result?.trim() ?? '';
    if (newText.isEmpty || newText == comment.text) return;

    final email = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
    if (email.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse(_editUrl),
        body: {
          'comment_id': '${comment.id}',
          'user_email': email,
          'comment_text': newText,
        },
      ).timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 || decoded['success'] != true) {
        throw Exception(decoded['error'] ?? 'فشل التعديل');
      }
      await _loadComments(silent: true);
    } catch (_) {
      _showSnack('فشل تعديل التعليق.', success: false);
    }
  }

  Future<void> _deleteComment(_PdfFileComment comment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        final bg = widget.isDark ? const Color(0xFF111111) : Colors.white;
        final textColor = widget.isDark ? Colors.white : const Color(0xFF17120A);
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: bg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('حذف التعليق؟', style: TextStyle(color: textColor, fontWeight: FontWeight.w900)),
            content: Text('راح ينحذف نهائياً.', style: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black54, height: 1.6)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حذف', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        );
      },
    );
    if (confirm != true) return;

    final email = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
    try {
      final response = await http.post(
        Uri.parse(_deleteUrl),
        body: {
          'comment_id': '${comment.id}',
          'user_email': email,
          'is_supervisor': _isSupervisor ? '1' : '0',
        },
      ).timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 || decoded['success'] != true) {
        throw Exception(decoded['error'] ?? 'فشل الحذف');
      }
      if (!mounted) return;
      setState(() => _comments.removeWhere((c) => c.id == comment.id));
    } catch (_) {
      _showSnack('فشل حذف التعليق.', success: false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_commentsScroll.hasClients) return;
      _commentsScroll.animateTo(
        _commentsScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _showSnack(String message, {required bool success}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          backgroundColor: Colors.transparent,
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 86),
          padding: EdgeInsets.zero,
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(
                  colors: success
                      ? const [Color(0xFF1F7A45), Color(0xFF0F4D2E)]
                      : const [Color(0xFFB3261E), Color(0xFF6E1511)],
                ),
              ),
              child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, height: 1.45)),
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = widget.isDark ? const Color(0xFFEDEDED) : const Color(0xFF17120A);
    final textSub = widget.isDark ? Colors.white70 : Colors.black54;
    final inputBg = widget.isDark ? const Color(0xFF171717) : const Color(0xFFF8F6F0);
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUserName = (currentUser?.displayName ?? currentUser?.email ?? 'مستخدم').trim();
    final currentUserAvatar = (currentUser?.photoURL ?? '').trim();

    return _DetailSectionCard(
      isDark: widget.isDark,
      surface: widget.surface,
      title: 'التعليقات',
      icon: Icons.chat_bubble_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: gold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: gold.withOpacity(0.24)),
                ),
                child: Text(
                  '${_comments.length} تعليق',
                  style: TextStyle(color: gold, fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
              const Spacer(),
              if (_loading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: gold),
                ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: _loading
                ? Padding(
                    key: const ValueKey('loading_comments'),
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(color: gold)),
                  )
                : _error != null
                    ? _CommentsEmptyState(
                        key: const ValueKey('error_comments'),
                        icon: Icons.wifi_off_rounded,
                        title: _error!,
                        subtitle: 'اضغط لإعادة المحاولة.',
                        isDark: widget.isDark,
                        onTap: () => _loadComments(initial: true),
                      )
                    : _comments.isEmpty
                        ? _CommentsEmptyState(
                            key: const ValueKey('empty_comments'),
                            icon: Icons.mode_comment_outlined,
                            title: 'لا توجد تعليقات بعد',
                            subtitle: 'كن أول من يضيف تعليق.',
                            isDark: widget.isDark,
                          )
                        : ListView.separated(
                            key: const ValueKey('comments_list'),
                            controller: _commentsScroll,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _comments.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final comment = _comments[index];
                              final currentEmail = FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase() ?? '';
                              final ownsComment = currentEmail.isNotEmpty && currentEmail == comment.userEmail.trim().toLowerCase();
                              return _PdfCommentBubble(
                                comment: comment,
                                isDark: widget.isDark,
                                canEdit: ownsComment,
                                canDelete: ownsComment || _isSupervisor,
                                onEdit: () => _editComment(comment),
                                onDelete: () => _deleteComment(comment),
                              );
                            },
                          ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: inputBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: gold.withOpacity(_commentFocus.hasFocus ? 0.42 : 0.18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(widget.isDark ? 0.16 : 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              textDirection: TextDirection.rtl,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCubic,
                  child: _CommentAvatar(
                    key: ValueKey(currentUserAvatar.isNotEmpty ? currentUserAvatar : currentUserName),
                    url: currentUserAvatar,
                    name: currentUserName,
                    isDark: widget.isDark,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    controller: _commentCtrl,
                    focusNode: _commentFocus,
                    textDirection: TextDirection.rtl,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 1000,
                    style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w700, height: 1.55),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: FirebaseAuth.instance.currentUser == null ? 'سجل دخولك لإضافة تعليق...' : 'اكتب تعليقك...',
                      hintStyle: TextStyle(color: textSub.withOpacity(0.72), fontSize: 13.5, fontWeight: FontWeight.w700),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _commentCtrl,
                  builder: (_, value, __) {
                    final visible = value.text.trim().isNotEmpty;
                    return AnimatedScale(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutBack,
                      scale: visible ? 1 : 0,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        opacity: visible ? 1 : 0,
                        child: IgnorePointer(
                          ignoring: !visible || _sending,
                          child: GestureDetector(
                            onTap: _sendComment,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                  colors: [Color(0xFFF2C14E), Color(0xFFD4A017)],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: gold.withOpacity(0.26),
                                    blurRadius: 14,
                                    offset: const Offset(0, 7),
                                  ),
                                ],
                              ),
                              child: _sending
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(strokeWidth: 2.3, color: Colors.black),
                                    )
                                  : const Icon(Icons.send_rounded, color: Colors.black, size: 20),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfCommentBubble extends StatelessWidget {
  final _PdfFileComment comment;
  final bool isDark;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PdfCommentBubble({
    required this.comment,
    required this.isDark,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  static const gold = Color(0xFFD4A017);

  DateTime? _parseCommentTime(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;

    final normalized = raw.replaceFirst(' ', 'T');
    final hasExplicitZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(normalized);
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return null;

    if (hasExplicitZone) return parsed.toLocal();

    // تواريخ الخادم للتعليقات تصل غالباً بدون منطقة زمنية لكنها محفوظة كـ UTC.
    // تحويلها كـ UTC يمنع ظهور التعليق الجديد وكأنه مرّت عليه 3 ساعات، لأن حتى الوقت قرر يسوي دراما.
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    ).toLocal();
  }

  String get _timeText {
    if (comment.createdAt.isEmpty) return '';
    final parsed = _parseCommentTime(comment.createdAt);
    if (parsed == null) return comment.createdAt.split(' ').first;

    final now = DateTime.now();
    final diff = now.difference(parsed);
    if (diff.isNegative || diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
    if (diff.inDays < 7) return 'قبل ${diff.inDays} ي';
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? const Color(0xFFEDEDED) : const Color(0xFF17120A);
    final textSub = isDark ? Colors.white60 : Colors.black45;
    final bubble = isDark ? const Color(0xFF171717) : const Color(0xFFFFFCF5);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        alignment: Alignment.topRight,
        child: child,
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bubble,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gold.withOpacity(isDark ? 0.16 : 0.20)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          textDirection: TextDirection.rtl,
          children: [
            _CommentAvatar(url: comment.userAvatar, name: comment.userName, isDark: isDark),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Expanded(
                        child: Text(
                          comment.userName.isEmpty ? 'مستخدم' : comment.userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(color: textPrimary, fontSize: 13.5, fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (_timeText.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(_timeText, style: TextStyle(color: textSub, fontSize: 11.5, fontWeight: FontWeight.w800)),
                      ],
                      if (canEdit || canDelete) ...[
                        const SizedBox(width: 2),
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: Icon(Icons.more_horiz_rounded, color: textSub, size: 20),
                          color: isDark ? const Color(0xFF191919) : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          onSelected: (value) {
                            if (value == 'edit') onEdit();
                            if (value == 'delete') onDelete();
                          },
                          itemBuilder: (_) => [
                            if (canEdit)
                              const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                            if (canDelete)
                              const PopupMenuItem(value: 'delete', child: Text('حذف')),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    comment.text,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13.5, height: 1.65, fontWeight: FontWeight.w700),
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

class _CommentAvatar extends StatelessWidget {
  final String url;
  final String name;
  final bool isDark;

  const _CommentAvatar({super.key, required this.url, required this.name, required this.isDark});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '؟' : name.trim().characters.first;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF2A2110), Color(0xFF111111)]
              : const [Color(0xFFFFF0C2), Color(0xFFFFFFFF)],
        ),
        border: Border.all(color: gold.withOpacity(0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? Center(
              child: Text(
                initial,
                style: const TextStyle(color: gold, fontWeight: FontWeight.w900, fontSize: 15),
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(initial, style: const TextStyle(color: gold, fontWeight: FontWeight.w900, fontSize: 15)),
              ),
            ),
    );
  }
}

class _CommentsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback? onTap;

  const _CommentsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    this.onTap,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF171717) : const Color(0xFFFFFCF5),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gold.withOpacity(0.16)),
        ),
        child: Column(
          children: [
            Icon(icon, color: gold.withOpacity(0.85), size: 30),
            const SizedBox(height: 9),
            Text(title, textAlign: TextAlign.center, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF17120A), fontWeight: FontWeight.w900, fontSize: 14)),
            const SizedBox(height: 5),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: isDark ? Colors.white60 : Colors.black45, fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.5)),
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
  bool _viewerDownloading = false;
  double _viewerDownloadProgress = 0;

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

  void _showViewerSnack({required String message, required bool success}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          padding: EdgeInsets.zero,
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: success
                      ? const [Color(0xFF1F7A45), Color(0xFF0F4D2E)]
                      : const [Color(0xFFB3261E), Color(0xFF6E1511)],
                ),
                border: Border.all(color: Colors.white.withOpacity(0.16)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.20),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      success ? Icons.check_rounded : Icons.error_outline_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        height: 1.45,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }

  Future<void> _downloadPdfFromViewer() async {
    if (_viewerDownloading) return;
    HapticFeedback.lightImpact();
    setState(() {
      _viewerDownloading = true;
      _viewerDownloadProgress = 0.001;
    });

    IOSink? output;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final localFile = File('${dir.path}/${widget.file.safeFileName}');
      final tempFile = File('${dir.path}/.${widget.file.safeFileName}.viewerdownload');
      if (await tempFile.exists()) await tempFile.delete();

      final request = await HttpClient().getUrl(Uri.parse(widget.file.fileUrl));
      final response = await request.close();
      if (response.statusCode != 200) throw Exception('فشل التحميل');

      output = tempFile.openWrite();
      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      await for (final chunk in response) {
        receivedBytes += chunk.length;
        output.add(chunk);
        if (mounted) {
          setState(() {
            _viewerDownloadProgress = totalBytes > 0
                ? (receivedBytes / totalBytes).clamp(0.001, 0.999).toDouble()
                : 0.001;
          });
        }
      }

      await output.flush();
      await output.close();
      output = null;

      if (await localFile.exists()) await localFile.delete();
      await tempFile.rename(localFile.path);

      if (!mounted) return;
      setState(() {
        _localPath = localFile.path;
        _viewerDownloading = false;
        _viewerDownloadProgress = 1;
      });
      _showViewerSnack(message: 'تم تحميل الملف بنجاح ✓', success: true);

      Future.delayed(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        setState(() => _viewerDownloadProgress = 0);
      });
    } catch (_) {
      try { await output?.close(); } catch (_) {}
      if (!mounted) return;
      setState(() {
        _viewerDownloading = false;
        _viewerDownloadProgress = 0;
      });
      _showViewerSnack(message: 'فشل التحميل. تحقق من الاتصال', success: false);
    }
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
    borderRadius: BorderRadius.circular(50),
    onTap: () => Navigator.pop(context),
    child: const Padding(
      padding: EdgeInsets.all(10),
      child: Icon(
        Icons.arrow_back_ios_new_rounded,
        color: Color(0xFFD4A017),
        size: 22,
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
                    // ── Page Counter ───────────────────────────────────
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4A017).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFD4A017).withOpacity(0.24),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.menu_book_rounded,
                            color: Color(0xFFD4A017),
                            size: 17,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _totalPages <= 0 ? '...' : '${_currentPage + 1}/$_totalPages',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: text,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ── Download Button ──────────────────────────────────
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _viewerDownloading ? null : _downloadPdfFromViewer,
                        child: Container(
                          width: 44,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4A017).withOpacity(_viewerDownloading ? 0.18 : 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFFD4A017).withOpacity(_viewerDownloading ? 0.38 : 0.0),
                            ),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (_viewerDownloading)
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: LinearProgressIndicator(
                                      value: _viewerDownloadProgress <= 0.001
                                          ? null
                                          : _viewerDownloadProgress,
                                      backgroundColor: Colors.transparent,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        const Color(0xFFD4A017).withOpacity(0.28),
                                      ),
                                    ),
                                  ),
                                ),
                              _viewerDownloading
                                  ? Text(
                                      '${(_viewerDownloadProgress * 100).clamp(0, 100).round()}%',
                                      style: const TextStyle(
                                        color: Color(0xFFD4A017),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.download_rounded,
                                      color: Color(0xFFD4A017),
                                      size: 20,
                                    ),
                            ],
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
  String _selectedCategory = kPdfDefaultCategories.first;
  final _customCategoryCtrl = TextEditingController();
  bool _useCustomCategory = false;
  bool _publishing = false;
  bool _expanded = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _customCategoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
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
    final categoryValue = (_useCustomCategory ? _customCategoryCtrl.text : _selectedCategory).trim();
    if (categoryValue.isEmpty) { _showSnack('اختر تصنيف أو أضف تصنيف جديد'); return; }
    setState(() => _publishing = true);
    try {
      final req = http.MultipartRequest('POST', Uri.parse(_addApi));
      req.fields['title'] = _titleCtrl.text.trim();
      req.fields['description'] = _descCtrl.text.trim();
      req.fields['category'] = categoryValue;
      req.files.add(await http.MultipartFile.fromPath('pdf_file', _pickedPdf!.path));
      final res = await req.send().timeout(const Duration(seconds: 60));
      if (res.statusCode == 200 || res.statusCode == 302) {
        _titleCtrl.clear(); _descCtrl.clear(); _customCategoryCtrl.clear();
        setState(() { _pickedPdf = null; _pdfName = ''; _selectedCategory = kPdfDefaultCategories.first; _useCustomCategory = false; _expanded = false; _publishing = false; });
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
                    _PdfCategoryPicker(
                      isDark: isDark,
                      selectedCategory: _selectedCategory,
                      useCustom: _useCustomCategory,
                      customController: _customCategoryCtrl,
                      onCategoryChanged: (value) => setState(() {
                        _selectedCategory = value;
                        _useCustomCategory = false;
                      }),
                      onCustomModeChanged: (value) => setState(() => _useCustomCategory = value),
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
  final void Function(PdfFileItem) onDeleted;
  const _EditPdfSheet({
    required this.file,
    required this.isDark,
    required this.onSaved,
    required this.onDeleted,
  });
  @override
  State<_EditPdfSheet> createState() => _EditPdfSheetState();
}

class _EditPdfSheetState extends State<_EditPdfSheet> {
  static const gold = Color(0xFFD4A017);
  static const _updateApi = 'https://majidalbana.com/admin/pdf-posts/update_pdf_post.php';
  static const _deleteApi = 'https://majidalbana.com/admin/pdf-posts/delete_pdf_post.php';

  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _customCategoryCtrl;
  late String _selectedCategory;
  late bool _useCustomCategory;
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.file.title);
    _descCtrl = TextEditingController(text: widget.file.description);
    final known = kPdfDefaultCategories.contains(widget.file.category);
    _selectedCategory = known ? widget.file.category : kPdfDefaultCategories.first;
    _useCustomCategory = widget.file.category.isNotEmpty && !known;
    _customCategoryCtrl = TextEditingController(text: _useCustomCategory ? widget.file.category : '');
  }

  @override
  void dispose() { _titleCtrl.dispose(); _descCtrl.dispose(); _customCategoryCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) { _showSnack('العنوان مطلوب'); return; }
    final categoryValue = (_useCustomCategory ? _customCategoryCtrl.text : _selectedCategory).trim();
    if (categoryValue.isEmpty) { _showSnack('اختر تصنيف أو أضف تصنيف جديد'); return; }
    setState(() => _saving = true);
    try {
      final res = await http.post(Uri.parse(_updateApi), body: {
        'id': '${widget.file.id}',
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'category': categoryValue,
      }).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final updated = widget.file.copyWith(
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          category: categoryValue,
        );
        widget.onSaved(updated);
        if (mounted) Navigator.pop(context);
        _showSnack('تم التعديل بنجاح ✓', success: true);
      } else { _showSnack('فشل التعديل'); setState(() => _saving = false); }
    } catch (_) { _showSnack('خطأ في الاتصال'); setState(() => _saving = false); }
  }

  Future<void> _confirmDelete() async {
    FocusScope.of(context).unfocus();
    final isDark = widget.isDark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF17120A);
    final textSub = isDark ? Colors.white70 : Colors.black54;
    final dialogBg = isDark ? const Color(0xFF151515) : Colors.white;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: !_deleting,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: dialogBg,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            titlePadding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFE53935), size: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تأكيد حذف المنشور',
                    style: TextStyle(color: textPrimary, fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            content: Text(
              'سيتم حذف هذا المنشور نهائياً من الملفات. لا يمكن التراجع عن هذه العملية بعد التأكيد.',
              style: TextStyle(color: textSub, height: 1.7, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                style: TextButton.styleFrom(
                  foregroundColor: textSub,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                ),
                child: const Text('إلغاء', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                icon: const Icon(Icons.delete_rounded, size: 18),
                label: const Text('حذف نهائي', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      await _delete();
    }
  }

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() => _deleting = true);
    try {
      final res = await http.post(
        Uri.parse(_deleteApi),
        body: {'id': '${widget.file.id}'},
      ).timeout(const Duration(seconds: 30));

      final body = res.body.trim();
      final ok = res.statusCode == 200 &&
          (body.isEmpty ||
              body == 'Deleted' ||
              body.contains('success') ||
              body.contains('تم'));

      if (!ok) {
        throw Exception(body.isEmpty ? 'فشل الحذف' : body);
      }

      widget.onDeleted(widget.file);
      if (mounted) Navigator.pop(context);
      _showSnack('تم حذف المنشور بنجاح ✓', success: true);
    } catch (_) {
      if (mounted) {
        setState(() => _deleting = false);
        _showSnack('تعذر حذف المنشور. تأكد من الاتصال وحاول مجدداً.');
      }
    }
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
                  const SizedBox(height: 10),
                  _PdfCategoryPicker(
                    isDark: isDark,
                    selectedCategory: _selectedCategory,
                    useCustom: _useCustomCategory,
                    customController: _customCategoryCtrl,
                    onCategoryChanged: (value) => setState(() {
                      _selectedCategory = value;
                      _useCustomCategory = false;
                    }),
                    onCustomModeChanged: (value) => setState(() => _useCustomCategory = value),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: (_saving || _deleting) ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: gold,
                              foregroundColor: Colors.white,
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
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton(
                            onPressed: (_saving || _deleting) ? null : _confirmDelete,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFE53935),
                              side: BorderSide(color: const Color(0xFFE53935).withOpacity(0.55), width: 1.2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              backgroundColor: const Color(0xFFE53935).withOpacity(0.08),
                            ),
                            child: _deleting
                                ? const SizedBox(width: 21, height: 21, child: CircularProgressIndicator(color: Color(0xFFE53935), strokeWidth: 2.4))
                                : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    Icon(Icons.delete_outline_rounded, size: 18),
                                    SizedBox(width: 6),
                                    Text('حذف', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                                  ]),
                          ),
                        ),
                      ),
                    ],
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