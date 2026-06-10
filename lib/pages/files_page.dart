import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../widgets/shared_widgets.dart';

class FilesPage extends StatefulWidget {
  final bool isDark;
  const FilesPage({super.key, required this.isDark});

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  static const gold = Color(0xFFD4A017);

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

    // يفحص الملفات الجديدة تلقائياً بدون ما يحتاج المستخدم يطلع ويدخل.
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
        _error = 'تعذر تحميل الملفات. تأكد من الاتصال بالإنترنت.';
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
      final url = Uri.parse(file.fileUrl);
      final request = await HttpClient().getUrl(url);
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('فشل التحميل');
      }

      final dir = await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/${file.safeFileName}';
      final output = File(savePath).openWrite();

      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      await for (final chunk in response) {
        receivedBytes += chunk.length;
        output.add(chunk);

        if (totalBytes > 0 && mounted) {
          setState(() {
            _downloadProgress[file.id] = receivedBytes / totalBytes;
          });
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

  @override
  Widget build(BuildContext context) {
    final textPrimary = widget.isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = widget.isDark ? Colors.white60 : Colors.black54;
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
              child: Center(
                child: CircularProgressIndicator(color: gold),
              ),
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final file = _files[i];
                    final isDownloading = _downloading.contains(file.id);
                    final progress = _downloadProgress[file.id] ?? 0;
                    final isDownloaded = _downloaded.contains(file.id);

                    return _FileCard(
                      file: file,
                      isDark: widget.isDark,
                      textPrimary: textPrimary,
                      textSub: textSub,
                      isDownloading: isDownloading,
                      isDownloaded: isDownloaded,
                      progress: progress,
                      onDownload: () => _downloadFile(file),
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

  const PdfFileItem({
    required this.id,
    required this.title,
    required this.description,
    required this.fileName,
    required this.fileSize,
    required this.author,
    required this.thumbnail,
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
    );
  }

  static String _clean(dynamic value) {
    return '${value ?? ''}'.trim();
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
}

class _FileCard extends StatelessWidget {
  final PdfFileItem file;
  final bool isDark;
  final Color textPrimary;
  final Color textSub;
  final bool isDownloading;
  final bool isDownloaded;
  final double progress;
  final VoidCallback onDownload;

  const _FileCard({
    required this.file,
    required this.isDark,
    required this.textPrimary,
    required this.textSub,
    required this.isDownloading,
    required this.isDownloaded,
    required this.progress,
    required this.onDownload,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF181818) : Colors.white;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: gold.withOpacity(0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.24 : 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumbnail(file: file, isDark: isDark),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _FileBadge(extension: file.extension),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          file.title.isEmpty ? 'ملف بدون عنوان' : file.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 15,
                            height: 1.45,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (file.description.isNotEmpty)
                    Text(
                      file.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textSub,
                        fontSize: 13,
                        height: 1.55,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.person_rounded, size: 15, color: gold.withOpacity(0.9)),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          file.author,
                          style: TextStyle(
                            color: textSub,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(Icons.sd_storage_rounded, size: 15, color: textSub),
                      const SizedBox(width: 4),
                      Text(
                        file.fileSize.isEmpty ? 'غير معروف' : file.fileSize,
                        style: TextStyle(
                          color: textSub,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _DownloadButton(
                    isDownloading: isDownloading,
                    isDownloaded: isDownloaded,
                    progress: progress,
                    onPressed: onDownload,
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

class _Thumbnail extends StatelessWidget {
  final PdfFileItem file;
  final bool isDark;

  const _Thumbnail({
    required this.file,
    required this.isDark,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF101010) : const Color(0xFFF0ECE2);

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: bg,
        child: file.hasThumbnail
            ? Image.network(
                file.thumbnailUrl,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (_, __, ___) => _FallbackThumbnail(
                  extension: file.extension,
                  isDark: isDark,
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: gold,
                      value: progress.expectedTotalBytes == null
                          ? null
                          : progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!,
                    ),
                  );
                },
              )
            : _FallbackThumbnail(extension: file.extension, isDark: isDark),
      ),
    );
  }
}

class _FallbackThumbnail extends StatelessWidget {
  final String extension;
  final bool isDark;

  const _FallbackThumbnail({
    required this.extension,
    required this.isDark,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? const Color(0xFF101010) : const Color(0xFFF0ECE2),
      child: Center(
        child: Container(
          width: 86,
          height: 86,
          decoration: BoxDecoration(
            color: gold.withOpacity(0.12),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: gold.withOpacity(0.22)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.picture_as_pdf_rounded, color: gold, size: 34),
              const SizedBox(height: 6),
              Text(
                extension,
                style: const TextStyle(
                  color: gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileBadge extends StatelessWidget {
  final String extension;
  const _FileBadge({required this.extension});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: gold.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: gold.withOpacity(0.22)),
      ),
      child: Text(
        extension,
        style: const TextStyle(
          color: gold,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  final bool isDownloading;
  final bool isDownloaded;
  final double progress;
  final VoidCallback onPressed;

  const _DownloadButton({
    required this.isDownloading,
    required this.isDownloaded,
    required this.progress,
    required this.onPressed,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).clamp(0, 100).round();

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: isDownloading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: gold,
          disabledBackgroundColor: gold.withOpacity(0.72),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isDownloading)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: LinearProgressIndicator(
                    value: progress <= 0 ? null : progress,
                    backgroundColor: Colors.black.withOpacity(0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.black.withOpacity(0.16),
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
                const SizedBox(width: 8),
                Text(
                  isDownloading
                      ? 'جاري التحميل $percent%'
                      : isDownloaded
                          ? 'تم التحميل'
                          : 'تحميل الملف',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final bool isDark;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.isDark,
    required this.onRetry,
  });

  static const gold = Color(0xFFD4A017);

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
              backgroundColor: gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
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
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
