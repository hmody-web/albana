import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../widgets/shared_widgets.dart';

class FilesPage extends StatefulWidget {
  final bool isDark;
  const FilesPage({super.key, required this.isDark});

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  static const gold = Color(0xFFD4A017);
  static const darkCard = Color(0xFF111111);

  static const String _apiUrl =
      'https://majidalbana.com/admin/pdf-posts/load_pdf_posts.php';
  static const String _fileBaseUrl = 'https://majidalbana.com/uploads-pdf/';
  static const String _thumbBaseUrl = 'https://majidalbana.com/uploads-pdf/img/';

  final Map<int, double> _downloadProgress = {};
  final Set<int> _downloading = {};
  final Set<int> _downloaded = {};

  List<PdfFileItem> _files = [];
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadFiles(showLoading: true);
    _refreshTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _loadFiles(showLoading: false);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFiles({required bool showLoading}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final uri = Uri.parse('$_apiUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      final request = await HttpClient().getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);

      if (decoded is! List) {
        throw Exception('صيغة البيانات غير صحيحة');
      }

      final loadedFiles = decoded
          .map((item) => PdfFileItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      if (!mounted) return;
      setState(() {
        _files = loadedFiles;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_files.isEmpty) {
          _error = 'تعذر تحميل الملفات. تأكد من الاتصال بالإنترنت.';
        }
      });
    }
  }

  Future<void> _downloadFile(PdfFileItem file) async {
    if (_downloading.contains(file.id)) return;

    setState(() {
      _downloading.add(file.id);
      _downloadProgress[file.id] = 0;
    });

    try {
      final request = await HttpClient().getUrl(Uri.parse(file.fileUrl));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('فشل التحميل');
      }

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

  @override
  Widget build(BuildContext context) {
    final pageBg = widget.isDark ? const Color(0xFF050505) : const Color(0xFFF8F6F0);

    return Container(
      color: pageBg,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          PremiumAppBar(title: 'الملفات', isDark: widget.isDark),
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
                onRetry: () => _loadFiles(showLoading: true),
              ),
            )
          else if (_files.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(isDark: widget.isDark),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 105),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final file = _files[i];
                    return _FileCard(
                      file: file,
                      isDark: widget.isDark,
                      isDownloading: _downloading.contains(file.id),
                      isDownloaded: _downloaded.contains(file.id),
                      progress: _downloadProgress[file.id] ?? 0,
                      onDownload: () => _downloadFile(file),
                      onView: () => _openFile(file),
                    );
                  },
                  childCount: _files.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

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

class _FileCard extends StatelessWidget {
  final PdfFileItem file;
  final bool isDark;
  final bool isDownloading;
  final bool isDownloaded;
  final double progress;
  final VoidCallback onDownload;
  final VoidCallback onView;

  const _FileCard({
    required this.file,
    required this.isDark,
    required this.isDownloading,
    required this.isDownloaded,
    required this.progress,
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
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06)),
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
                  Text(
                    file.title.isEmpty ? 'ملف بدون عنوان' : file.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
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
                            Text(
                              file.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
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
                  _FileInfoPill(file: file, isDark: isDark),
                  if (file.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      file.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
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
              errorBuilder: (_, __, ___) => _FallbackThumbnail(extension: file.extension, isDark: isDark),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: gold,
                    value: progress.expectedTotalBytes == null
                        ? null
                        : progress.cumulativeBytesLoaded / progress.expectedTotalBytes!,
                  ),
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
          colors: [Color(0xFFD4A017), Color(0xFF2E6BFF)],
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

class _FileInfoPill extends StatelessWidget {
  final PdfFileItem file;
  final bool isDark;
  const _FileInfoPill({required this.file, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D2134) : const Color(0xFFF2F4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF5567FF).withOpacity(0.16)),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF34418E).withOpacity(0.72),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              file.fileSize.isEmpty ? 'PDF' : file.fileSize,
              style: const TextStyle(
                color: Color(0xFF91A2FF),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              file.fileName.isEmpty ? 'ملف PDF' : file.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF172033),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Icon(Icons.attach_file_rounded, size: 18, color: isDark ? Colors.white38 : Colors.black38),
        ],
      ),
    );
  }
}

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
          backgroundColor: isDark ? const Color(0xFF202337) : const Color(0xFFF1F3FF),
          foregroundColor: isDark ? const Color(0xFFE8D2B0) : const Color(0xFF49351B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: const Color(0xFF6370FF).withOpacity(0.24)),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

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
          backgroundColor: isDark ? const Color(0xFF202337) : const Color(0xFFF1F3FF),
          disabledBackgroundColor: isDark ? const Color(0xFF202337) : const Color(0xFFF1F3FF),
          foregroundColor: isDark ? const Color(0xFFE8D2B0) : const Color(0xFF49351B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: const Color(0xFF6370FF).withOpacity(0.24)),
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

class _PdfBrowserPageState extends State<_PdfBrowserPage> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    final viewerUrl = Uri.parse(
      'https://docs.google.com/gview?embedded=1&url=${Uri.encodeComponent(widget.file.fileUrl)}',
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(widget.isDark ? const Color(0xFF050505) : Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) => setState(() => _progress = value),
          onPageStarted: (_) => setState(() => _hasError = false),
          onWebResourceError: (_) => setState(() => _hasError = true),
        ),
      )
      ..loadRequest(viewerUrl);
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
              Container(
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.16)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(widget.isDark ? 0.25 : 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: text, size: 20),
                    ),
                    const _SmallLogo(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'عرض الملف',
                            style: TextStyle(
                              color: text.withOpacity(0.68),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            widget.file.title.isEmpty ? widget.file.fileName : widget.file.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: text,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_progress < 100 && !_hasError)
                LinearProgressIndicator(
                  value: _progress <= 0 ? null : _progress / 100,
                  color: const Color(0xFFD4A017),
                  backgroundColor: Colors.transparent,
                  minHeight: 2,
                ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white.withOpacity(widget.isDark ? 0.07 : 0.0)),
                  ),
                  child: _hasError
                      ? _ViewerError(
                          isDark: widget.isDark,
                          onRetry: () {
                            setState(() => _hasError = false);
                            _controller.reload();
                          },
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
        gradient: LinearGradient(colors: [Color(0xFFD4A017), Color(0xFF2E6BFF)]),
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/majid.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.white,
            child: const Icon(Icons.menu_book_rounded, color: Color(0xFFD4A017), size: 24),
          ),
        ),
      ),
    );
  }
}

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
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4A017),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

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
            border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.25)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFD4A017), size: 36),
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

class _ErrorState extends StatelessWidget {
  final String message;
  final bool isDark;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.isDark, required this.onRetry});

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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isDark;
  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = isDark ? Colors.white70 : Colors.black54;
    return Center(
      child: Text(
        'لا توجد ملفات حالياً',
        style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }
}
