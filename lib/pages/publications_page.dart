import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource, XFile;
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/shared_widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource, XFile;
import 'package:path_provider/path_provider.dart';
class PublicationsPage extends StatefulWidget {
  final bool isDark;
  const PublicationsPage({super.key, required this.isDark});

  @override
  State<PublicationsPage> createState() => _PublicationsPageState();
}

class _PublicationsPageState extends State<PublicationsPage> {
  static const gold = Color(0xFFD4A017);
  static const String _postsApi =
      'https://majidalbana.com/admin/posts/load_posts.php';
  static const String _addPostApi =
      'https://majidalbana.com/admin/posts/add_post.php';
  static const String _cacheKey = 'cached_posts';

  List<_PublicationPost> _posts = [];
  bool _initialLoading = true;
  bool _isOffline = false;
  Set<int> _cachedIds = {};
  Timer? _pollingTimer;

  bool _isSupervisor() {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email?.trim().toLowerCase();
    return email == 'hmode.qq@gmail.com' || email == 'hmode.qu@gmail.com';
  }

  @override
  void initState() {
    super.initState();
    _initPosts();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _initPosts() async {
    final cached = await _loadFromCache();
    if (cached.isNotEmpty) {
      _cachedIds = cached.map((p) => p.id).toSet();
      setState(() {
        _posts = cached;
        _initialLoading = false;
      });
    }
    await _fetchAndUpdate(showLoadingIfEmpty: cached.isEmpty);
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchAndUpdate(showLoadingIfEmpty: false);
    });
  }

  Future<List<_PublicationPost>> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) =>
              _PublicationPost.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveToCache(List<_PublicationPost> posts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(posts.map((p) => p.toJson()).toList());
      await prefs.setString(_cacheKey, raw);
    } catch (_) {}
  }

  Future<void> _fetchAndUpdate({bool showLoadingIfEmpty = false}) async {
    if (showLoadingIfEmpty && _posts.isEmpty) {
      setState(() => _initialLoading = true);
    }

    try {
      final response = await http
          .get(Uri.parse(_postsApi))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        if (_posts.isEmpty) setState(() => _initialLoading = false);
        setState(() => _isOffline = true);
        return;
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) {
        if (_posts.isEmpty) setState(() => _initialLoading = false);
        return;
      }

      final freshPosts = decoded
          .whereType<Map>()
          .map((item) =>
              _PublicationPost.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      final newPosts =
          freshPosts.where((p) => !_cachedIds.contains(p.id)).toList();

      if (newPosts.isNotEmpty || _initialLoading) {
        final merged = [...newPosts, ..._posts];
        _cachedIds = merged.map((p) => p.id).toSet();
        setState(() {
          _posts = merged;
          _initialLoading = false;
          _isOffline = false;
        });
        await _saveToCache(merged);
      } else {
        if (_isOffline) setState(() => _isOffline = false);
        if (_initialLoading) setState(() => _initialLoading = false);
      }
    } catch (_) {
      setState(() {
        _isOffline = true;
        if (_initialLoading) _initialLoading = false;
      });
    }
  }

  Future<void> _refreshPosts() async {
    await _fetchAndUpdate(showLoadingIfEmpty: false);
  }

  void _onPostPublished() {
    _cachedIds = {};
    _fetchAndUpdate(showLoadingIfEmpty: false);
  }

  void _onPostEdited(_PublicationPost updated) {
    setState(() {
      final idx = _posts.indexWhere((p) => p.id == updated.id);
      if (idx != -1) _posts[idx] = updated;
    });
    _saveToCache(_posts);
  }

  void _onPostDeleted(int id) {
    setState(() {
      _posts.removeWhere((p) => p.id == id);
      _cachedIds.remove(id);
    });
    _saveToCache(_posts);
  }

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.isDark ? const Color(0xFF101010) : const Color(0xFFF7F4EE);

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const BouncingScrollPhysics(),
      slivers: [
        PremiumAppBar(title: 'المنشورات', isDark: widget.isDark),
        SliverFillRemaining(
          hasScrollBody: true,
          child: Container(
            color: bgColor,
            child: _buildBody(),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator(color: gold));
    }

    if (_isOffline && _posts.isEmpty) {
      return _StateMessage(
        isDark: widget.isDark,
        icon: Icons.wifi_off_rounded,
        title: 'لا يوجد اتصال بالإنترنت',
        message: 'تحقق من الاتصال ثم حاول مجدداً.',
        buttonText: 'إعادة المحاولة',
        onPressed: () => _fetchAndUpdate(showLoadingIfEmpty: true),
      );
    }

    final supervisor = _isSupervisor();

    return RefreshIndicator(
      color: gold,
      onRefresh: _refreshPosts,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: (_posts.isEmpty ? 1 : _posts.length) + (supervisor ? 1 : 0),
        itemBuilder: (context, index) {
          if (supervisor && index == 0) {
            return _AdminPublishBox(
              isDark: widget.isDark,
              addPostApi: _addPostApi,
              onPublished: _onPostPublished,
            );
          }

          final postIndex = supervisor ? index - 1 : index;

          if (_posts.isEmpty) {
            return _StateMessage(
              isDark: widget.isDark,
              icon: Icons.article_outlined,
              title: 'لا توجد منشورات',
              message: 'أضف منشوراً من الصندوق أعلاه.',
              buttonText: 'تحديث',
              onPressed: _refreshPosts,
            );
          }

          final post = _posts[postIndex];
          final isCached = _cachedIds.contains(post.id);
          return _PostCard(
            post: post,
            isDark: widget.isDark,
            showOfflineBanner: _isOffline && !isCached,
            isSupervisor: supervisor,
            onEdited: _onPostEdited,
            onDeleted: _onPostDeleted,
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Publish Box
// ─────────────────────────────────────────────────────────────────────────────

class _AdminPublishBox extends StatefulWidget {
  final bool isDark;
  final String addPostApi;
  final VoidCallback onPublished;

  const _AdminPublishBox({
    required this.isDark,
    required this.addPostApi,
    required this.onPublished,
  });

  @override
  State<_AdminPublishBox> createState() => _AdminPublishBoxState();
}

class _AdminPublishBoxState extends State<_AdminPublishBox> {
  static const gold = Color(0xFFD4A017);
  final _contentCtrl = TextEditingController();
  List<File> _pickedImages = [];
  File? _pickedVideo;
  Duration? _videoDuration;
  bool _publishing = false;
  bool _expanded = false;
  // 'image' or 'video'
  String _mediaType = 'image';

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remaining = 4 - _pickedImages.length;
    if (remaining <= 0) return;
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 85);
    if (picked.isEmpty) return;
    setState(() {
      _pickedImages.addAll(
        picked.take(remaining).map((x) => File(x.path)),
      );
    });
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 2),
    );
    if (picked == null) return;

    // التحقق من مدة الفيديو
    final videoFile = File(picked.path);
    final ctrl = VideoPlayerController.file(videoFile);
    await ctrl.initialize();
    final duration = ctrl.value.duration;
    await ctrl.dispose();

    if (duration.inSeconds > 120) {
      if (mounted) _showSnack('الفيديو يتجاوز الدقيقتين — اختر فيديو أقصر');
      return;
    }

    setState(() {
      _pickedVideo = videoFile;
      _videoDuration = duration;
    });
  }

  void _removeImage(int index) {
    setState(() => _pickedImages.removeAt(index));
  }

  void _removeVideo() {
    setState(() {
      _pickedVideo = null;
      _videoDuration = null;
    });
  }

  Future<void> _publish() async {
    if (_mediaType == 'image' && _pickedImages.isEmpty) {
      _showSnack('الصورة مطلوبة للنشر');
      return;
    }
    if (_mediaType == 'video' && _pickedVideo == null) {
      _showSnack('الفيديو مطلوب للنشر');
      return;
    }

    setState(() => _publishing = true);
    try {
      final request =
          http.MultipartRequest('POST', Uri.parse(widget.addPostApi));
      request.fields['content'] = _contentCtrl.text.trim();

      if (_mediaType == 'video') {
        request.files.add(
          await http.MultipartFile.fromPath('video', _pickedVideo!.path),
        );
      } else {
        for (final img in _pickedImages) {
          request.files.add(
            await http.MultipartFile.fromPath('images[]', img.path),
          );
        }
      }

      final streamed =
          await request.send().timeout(const Duration(seconds: 60));
      if (streamed.statusCode == 200 || streamed.statusCode == 302) {
        _contentCtrl.clear();
        setState(() {
          _pickedImages = [];
          _pickedVideo = null;
          _videoDuration = null;
          _expanded = false;
          _publishing = false;
        });
        _showSnack('تم النشر بنجاح ✓', success: true);
        if (mounted) widget.onPublished();
      } else {
        _showSnack('فشل النشر. حاول مجدداً');
        setState(() => _publishing = false);
      }
    } catch (_) {
      _showSnack('خطأ في الاتصال');
      setState(() => _publishing = false);
    }
  }

  void _showSnack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor:
          success ? const Color(0xFF2E7D32) : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(14),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final cardBg = isDark ? const Color(0xFF181818) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final hintColor = isDark ? Colors.white38 : Colors.black38;
    final fieldBg =
        isDark ? const Color(0xFF232323) : const Color(0xFFFAF6EF);
    final borderColor = gold.withOpacity(0.35);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: gold.withOpacity(0.4), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: gold.withOpacity(isDark ? 0.12 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      gold.withOpacity(isDark ? 0.22 : 0.14),
                      gold.withOpacity(isDark ? 0.08 : 0.04),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: gold.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.add_rounded,
                          color: gold, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'نشر منشور جديد',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          color: gold, size: 24),
                    ),
                  ],
                ),
              ),
            ),

            // Expandable body
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // تبويب نوع المحتوى: صور / فيديو
                    Container(
                      decoration: BoxDecoration(
                        color: fieldBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _mediaType = 'image'),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                height: 36,
                                decoration: BoxDecoration(
                                  color: _mediaType == 'image'
                                      ? gold
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.image_rounded,
                                        size: 16,
                                        color: _mediaType == 'image'
                                            ? Colors.white
                                            : hintColor),
                                    const SizedBox(width: 6),
                                    Text('صور',
                                        style: TextStyle(
                                            color: _mediaType == 'image'
                                                ? Colors.white
                                                : hintColor,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _mediaType = 'video'),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                height: 36,
                                decoration: BoxDecoration(
                                  color: _mediaType == 'video'
                                      ? gold
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.videocam_rounded,
                                        size: 16,
                                        color: _mediaType == 'video'
                                            ? Colors.white
                                            : hintColor),
                                    const SizedBox(width: 6),
                                    Text('فيديو',
                                        style: TextStyle(
                                            color: _mediaType == 'video'
                                                ? Colors.white
                                                : hintColor,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // محتوى الوسائط
                    if (_mediaType == 'image')
                      _ImagesPickerGrid(
                        images: _pickedImages,
                        onAdd: _pickImages,
                        onRemove: _removeImage,
                        fieldBg: fieldBg,
                        borderColor: borderColor,
                        hintColor: hintColor,
                        gold: gold,
                      )
                    else
                      _VideoPickerBox(
                        videoFile: _pickedVideo,
                        duration: _videoDuration,
                        onPick: _pickVideo,
                        onRemove: _removeVideo,
                        fieldBg: fieldBg,
                        borderColor: borderColor,
                        hintColor: hintColor,
                        gold: gold,
                      ),
                    const SizedBox(height: 12),
                    // Content field
                    Container(
                      decoration: BoxDecoration(
                        color: fieldBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                      ),
                      child: TextField(
                        controller: _contentCtrl,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        maxLines: 5,
                        minLines: 3,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 14.5,
                          height: 1.7,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'اكتب وصفاً للمنشور...',
                          hintTextDirection: TextDirection.rtl,
                          hintStyle: TextStyle(
                              color: hintColor,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w400),
                          contentPadding: const EdgeInsets.all(14),
                          border: InputBorder.none,
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
                          backgroundColor: gold,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              gold.withOpacity(0.5),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _publishing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.send_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('نشر المنشور',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800)),
                                ],
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Images Picker Grid (up to 4 images)
// ─────────────────────────────────────────────────────────────────────────────

class _ImagesPickerGrid extends StatelessWidget {
  final List<File> images;
  final VoidCallback onAdd;
  final void Function(int) onRemove;
  final Color fieldBg;
  final Color borderColor;
  final Color hintColor;
  final Color gold;

  const _ImagesPickerGrid({
    required this.images,
    required this.onAdd,
    required this.onRemove,
    required this.fieldBg,
    required this.borderColor,
    required this.hintColor,
    required this.gold,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return GestureDetector(
        onTap: onAdd,
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            color: fieldBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_rounded,
                  color: gold.withOpacity(0.7), size: 32),
              const SizedBox(height: 7),
              Text('اضغط لإرفاق صور (حتى 4)',
                  style: TextStyle(
                      color: hintColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    final canAddMore = images.length < 4;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: images.length + (canAddMore ? 1 : 0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.3,
      ),
      itemBuilder: (context, index) {
        if (index == images.length) {
          // Add-more tile
          return GestureDetector(
            onTap: onAdd,
            child: Container(
              decoration: BoxDecoration(
                color: fieldBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: 1.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_rounded,
                      color: gold.withOpacity(0.7), size: 26),
                  const SizedBox(height: 5),
                  Text('إضافة صورة',
                      style: TextStyle(
                          color: hintColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          );
        }

        final img = images[index];
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(img, fit: BoxFit.cover),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: () => onRemove(index),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.85),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 15),
                ),
              ),
            ),
            if (index == 0)
              Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: gold.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('الرئيسية',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        );
      },
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// Video Picker Box
// ─────────────────────────────────────────────────────────────────────────────

class _VideoPickerBox extends StatelessWidget {
  final File? videoFile;
  final Duration? duration;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final Color fieldBg;
  final Color borderColor;
  final Color hintColor;
  final Color gold;

  const _VideoPickerBox({
    required this.videoFile,
    required this.duration,
    required this.onPick,
    required this.onRemove,
    required this.fieldBg,
    required this.borderColor,
    required this.hintColor,
    required this.gold,
  });

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (videoFile == null) {
      return GestureDetector(
        onTap: onPick,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: fieldBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.videocam_rounded, color: gold.withOpacity(0.7), size: 36),
              const SizedBox(height: 8),
              Text('اضغط لاختيار فيديو',
                  style: TextStyle(
                      color: hintColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('الحد الأقصى: دقيقتان',
                  style: TextStyle(
                      color: hintColor.withOpacity(0.7), fontSize: 11.5)),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gold.withOpacity(0.5), width: 1.5),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          const SizedBox(width: 16),
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: gold.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.videocam_rounded, color: gold, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  videoFile!.path.split('/').last,
                  textDirection: TextDirection.rtl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: hintColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                if (duration != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(Icons.timer_rounded, size: 13, color: gold),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(duration!),
                        style: TextStyle(
                            color: gold,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.red, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class _PublicationPost {
  final int id;
  final String image;
  final List<String> images;
  final String content;
  final String createdAt;

  const _PublicationPost({
    required this.id,
    required this.image,
    this.images = const [],
    required this.content,
    required this.createdAt,
  });

  factory _PublicationPost.fromJson(Map<String, dynamic> json) {
    final image = '${json['image'] ?? ''}';
    List<String> images = [];
    final rawImages = json['images'];
    if (rawImages is String && rawImages.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawImages);
        if (decoded is List) {
          images = decoded.map((e) => '$e').where((e) => e.isNotEmpty).toList();
        }
      } catch (_) {}
    } else if (rawImages is List) {
      images = rawImages.map((e) => '$e').where((e) => e.isNotEmpty).toList();
    }
    if (images.isEmpty && image.isNotEmpty) {
      images = [image];
    }
    return _PublicationPost(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      image: image,
      images: images,
      content: _cleanText('${json['content'] ?? ''}'),
      createdAt: '${json['created_at'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'image': image,
        'images': images,
        'content': content,
        'created_at': createdAt,
      };

  _PublicationPost copyWith({String? content, String? image, List<String>? images}) {
    return _PublicationPost(
      id: id,
      image: image ?? this.image,
      images: images ?? this.images,
      content: content ?? this.content,
      createdAt: createdAt,
    );
  }

  static String _cleanText(String value) {
    return value
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  String get imageUrl {
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return image;
    }
    return 'https://majidalbana.com/uploads/$image';
  }

  bool get isVideo {
    if (images.length == 1 && images.first == '__video__') return false;
    // تحقق من images JSON للعلامة الخاصة
    return false;
  }

  String? get videoUrl {
    // نتحقق من وجود مفتاح __video__ في images
    if (image.isNotEmpty) {
      final ext = image.split('.').last.toLowerCase();
      if (['mp4', 'mov', 'webm', '3gp'].contains(ext)) {
        if (image.startsWith('http://') || image.startsWith('https://')) {
          return image;
        }
        return 'https://majidalbana.com/uploads/$image';
      }
    }
    return null;
  }

  List<String> get imageUrls {
    if (videoUrl != null) return [];
    final list = images.isNotEmpty ? images : (image.isNotEmpty ? [image] : <String>[]);
    return list.map((img) {
      if (img.startsWith('http://') || img.startsWith('https://')) return img;
      return 'https://majidalbana.com/uploads/$img';
    }).toList();
  }

  String get formattedDate {
    if (createdAt.isEmpty) return 'منشور حديث';
    final parts = createdAt.split(RegExp(r'[ T]'));
    return parts.first;
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Comment Model
// ─────────────────────────────────────────────────────────────────────────────

class _Comment {
  final int id;
  final int postId;
  final String userName;
  final String userAvatar;
  final String text;
  final String createdAt;

  const _Comment({
    required this.id,
    required this.postId,
    required this.userName,
    required this.userAvatar,
    required this.text,
    required this.createdAt,
  });

  factory _Comment.fromJson(Map<String, dynamic> json) {
    return _Comment(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      postId: int.tryParse('${json['post_id'] ?? 0}') ?? 0,
      userName: '${json['user_name'] ?? 'مستخدم'}',
      userAvatar: '${json['user_avatar'] ?? ''}',
      text: '${json['comment_text'] ?? ''}',
      createdAt: '${json['created_at'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'post_id': postId,
    'user_name': userName,
    'user_avatar': userAvatar,
    'comment_text': text,
    'created_at': createdAt,
  };

  String get timeAgo {
    if (createdAt.isEmpty) return '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return '${diff.inSeconds}s';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      if (diff.inHours < 24) return '${diff.inHours}h';
      if (diff.inDays < 7) return '${diff.inDays}d';
      if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w';
      if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo';
      return '${(diff.inDays / 365).floor()}y';
    } catch (_) {
      return createdAt.split(' ').first;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Post Card
// ─────────────────────────────────────────────────────────────────────────────

class _PostCard extends StatefulWidget {
  final _PublicationPost post;
  final bool isDark;
  final bool showOfflineBanner;
  final bool isSupervisor;
  final void Function(_PublicationPost) onEdited;
  final void Function(int) onDeleted;

  const _PostCard({
    required this.post,
    required this.isDark,
    this.showOfflineBanner = false,
    required this.isSupervisor,
    required this.onEdited,
    required this.onDeleted,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  static const gold = Color(0xFFD4A017);
  static const String _commentsApi =
      'https://majidalbana.com/admin/comments/load_comments.php';
  static const String _addCommentApi =
      'https://majidalbana.com/admin/comments/add_comment.php';

  bool _expanded = false;
  bool _liked = false;
  int _likesCount = 0;
  bool _likeLoading = false;
  static const String _toggleLikeApi =
      'https://majidalbana.com/admin/posts/toggle_like.php';
  static const String _getLikesApi =
      'https://majidalbana.com/admin/posts/get_likes.php';
  final _commentCtrl = TextEditingController();
  bool _sendingComment = false;
  List<_Comment> _comments = [];
  bool _loadingComments = false;
  bool _commentsLoaded = false;
  Timer? _commentsPollingTimer;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    _loadCommentCount();
    _loadLikes();
  }

  Future<void> _loadLikes() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email ?? '';
      final uri = Uri.parse(_getLikesApi).replace(queryParameters: {
        'post_id': '${widget.post.id}',
        if (email.isNotEmpty) 'user_email': email,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is Map && data['success'] == true) {
          setState(() {
            _likesCount = int.tryParse('${data['likes_count'] ?? 0}') ?? 0;
            _liked = data['liked'] == true;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (_likeLoading) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || (user.email ?? '').isEmpty) {
      _showLoginSheet();
      return;
    }

    setState(() {
      _likeLoading = true;
      if (_liked) {
        _liked = false;
        _likesCount = (_likesCount - 1).clamp(0, 1 << 31);
      } else {
        _liked = true;
        _likesCount += 1;
      }
    });

    try {
      final res = await http.post(
        Uri.parse(_toggleLikeApi),
        body: {
          'post_id': '${widget.post.id}',
          'user_email': user.email ?? '',
        },
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is Map && data['success'] == true) {
          setState(() {
            _liked = data['liked'] == true;
            _likesCount =
                int.tryParse('${data['likes_count'] ?? _likesCount}') ??
                    _likesCount;
          });
        } else {
          await _loadLikes();
        }
      } else {
        await _loadLikes();
      }
    } catch (_) {
      if (mounted) await _loadLikes();
    } finally {
      if (mounted) setState(() => _likeLoading = false);
    }
  }

  @override
  void dispose() {
    _commentsPollingTimer?.cancel();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCommentCount() async {
    await _loadComments();
  }

  void _startCommentsPolling() {
    _commentsPollingTimer?.cancel();
    _commentsPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_sheetOpen) _silentReloadComments();
    });
  }

  void _stopCommentsPolling() {
    _commentsPollingTimer?.cancel();
    _commentsPollingTimer = null;
  }

  Future<void> _silentReloadComments() async {
    try {
      final res = await http.get(
        Uri.parse('$_commentsApi?post_id=${widget.post.id}'),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = utf8.decode(res.bodyBytes);
        final data = jsonDecode(body);
        if (data is List) {
          final loaded = data
              .whereType<Map>()
              .map((e) => _Comment.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          if (mounted) setState(() => _comments = loaded);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadComments() async {
    if (_loadingComments) return;
    setState(() => _loadingComments = true);
    try {
      final res = await http.get(
        Uri.parse('$_commentsApi?post_id=${widget.post.id}'),
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = utf8.decode(res.bodyBytes);
        final data = jsonDecode(body);
        if (data is List) {
          final loaded = data
              .whereType<Map>()
              .map((e) => _Comment.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          setState(() {
            _comments = loaded;
            _commentsLoaded = true;
          });
        } else if (data is Map && data['comments'] is List) {
          // fallback لو السيرفر يرجع { comments: [...] }
          final loaded = (data['comments'] as List)
              .whereType<Map>()
              .map((e) => _Comment.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          setState(() {
            _comments = loaded;
            _commentsLoaded = true;
          });
        }
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  Future<void> _sendComment() async {
    print('### _sendComment called ###');
    final text = _commentCtrl.text.trim();
    print('### text: $text ###');
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('اكتب تعليقاً أولاً', textDirection: TextDirection.rtl),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _sendingComment = true);
    try {
      final res = await http.post(
        Uri.parse(_addCommentApi),
        body: {
          'post_id': '${widget.post.id}',
          'user_name': user.displayName ?? 'مستخدم',
          'user_avatar': user.photoURL ?? '',
          'comment_text': text,
          'user_email': user.email ?? '',
        },
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      print('### status: ${res.statusCode} ###');
      print('### response: ${utf8.decode(res.bodyBytes)} ###');
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data['success'] == true) {
          _commentCtrl.clear();
          _commentsLoaded = false;
          await _loadComments();
        }
      }
    } catch (e, stack) {
      print('ERROR: $e');
      print('STACK: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('خطأ: $e',
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.all(14),
        ));
      }
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

Future<void> _editComment(int commentId, String newText) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      debugPrint('### EDIT HTTP START id=$commentId ###');
      final res = await http.post(
        Uri.parse('https://majidalbana.com/admin/comments/edit_comment.php'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'comment_id': '$commentId',
          'comment_text': newText,
          'user_email': user.email ?? '',
        },
      ).timeout(const Duration(seconds: 15));
      debugPrint('### EDIT STATUS: ${res.statusCode} ###');
      debugPrint('### EDIT BODY: ${utf8.decode(res.bodyBytes)} ###');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data['success'] == true) {
          setState(() {
            final idx = _comments.indexWhere((c) => c.id == commentId);
            if (idx != -1) {
              _comments[idx] = _Comment(
                id: _comments[idx].id,
                postId: _comments[idx].postId,
                userName: _comments[idx].userName,
                userAvatar: _comments[idx].userAvatar,
                text: newText,
                createdAt: _comments[idx].createdAt,
              );
            }
          });
        } else {
          _commentsLoaded = false;
          await _loadComments();
        }
      }
    } catch (e) {
      debugPrint('### EDIT ERROR: $e ###');
    }
  }

  Future<void> _deleteComment(int commentId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final res = await http.post(
        Uri.parse('https://majidalbana.com/admin/comments/delete_comment.php'),
        body: {
          'comment_id': '$commentId',
          'user_email': user.email ?? '',
        },
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      debugPrint('EDIT STATUS: ${res.statusCode}');
      debugPrint('EDIT BODY: ${utf8.decode(res.bodyBytes)}');
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        debugPrint('EDIT DATA: $data');
        if (data['success'] == true) {
          _commentsLoaded = false;
          await _loadComments();
        }
      }
    } catch (_) {}
  }

  void _openPostDetail() {
        Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: _PostDetailPage(
            post: widget.post,
            isDark: widget.isDark,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _openEditSheet() {
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditPostSheet(
        post: widget.post,
        isDark: widget.isDark,
        onSaved: widget.onEdited,
      ),
    ).then((result) {
      if (result == 'deleted' && mounted) {
        widget.onDeleted(widget.post.id);
      }
    });
  }

  void _showLoginSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LoginSheet(
        isDark: widget.isDark,
        onLoggedIn: () {
          setState(() {});
          Navigator.pop(context);
        },
      ),
    );
  }
void _openCommentsSheet({bool autoFocus = false}) {
    _sheetOpen = true;
    _startCommentsPolling();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) {
          _commentsPollingTimer?.cancel();
          _commentsPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
            if (!_sheetOpen) return;
            _silentReloadComments().then((_) {
              if (mounted) setSheetState(() {});
            });
          });

          return _CommentsBottomSheet(
            post: widget.post,
            isDark: widget.isDark,
            comments: _comments,
            loadingComments: _loadingComments,
            commentsLoaded: _commentsLoaded,
            commentCtrl: _commentCtrl,
            sendingComment: _sendingComment,
            autoFocus: autoFocus,
            onSend: () async {
              await _sendComment();
              if (mounted) setState(() {});
              setSheetState(() {});
            },
            onLoginTap: _showLoginSheet,
            onReload: () async {
              await _loadComments();
              setSheetState(() {});
            },
            onEdit: (id, newText) async {
              await _editComment(id, newText);
              if (mounted) setState(() {});
              setSheetState(() {});
            },
            onDelete: (id) async {
              await _deleteComment(id);
              if (mounted) setState(() {});
              setSheetState(() {});
            },
          );
        },
      ),
    ).whenComplete(() {
      _sheetOpen = false;
      _stopCommentsPolling();
    });
  }
  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final isDark = widget.isDark;
    final cardBg = isDark ? const Color(0xFF181818) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white60 : Colors.black54;
    final dividerColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.07);
    final fieldBg = isDark ? const Color(0xFF242424) : const Color(0xFFF5F1EA);
    final currentUser = FirebaseAuth.instance.currentUser;
    final commentCount = _comments.length;

    return GestureDetector(
      onTap: _openPostDetail,
      child: Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gold.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
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
            if (p.videoUrl != null)
              _PostVideoPlayer(
                videoUrl: p.videoUrl!,
                isDark: isDark,
                post: p,
              )
            else if (p.imageUrls.isNotEmpty)
              _PostImageGallery(
                imageUrls: p.imageUrls,
                isDark: isDark,
                onImageTap: _openPostDetail,
              ),

            if (widget.showOfflineBanner)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: Colors.orange.withOpacity(0.12),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        size: 14, color: Colors.orange),
                    const SizedBox(width: 7),
                    const Text(
                      'لا يوجد اتصال بالإنترنت — المحتوى غير متاح',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

            // Author Row
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage:
                        const AssetImage('assets/images/majid.png'),
                    backgroundColor: gold.withOpacity(0.15),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'د.ماجد البنا',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(Icons.calendar_month_rounded,
                                size: 12, color: textSub),
                            const SizedBox(width: 4),
                            Text(
                              p.formattedDate,
                              style:
                                  TextStyle(color: textSub, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.isSupervisor)
                    GestureDetector(
                      onTap: _openEditSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: gold.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: gold.withOpacity(0.4)),
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
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: p.content.isEmpty
                  ? Text(
                      'منشور بدون وصف',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 14.5,
                        height: 1.75,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  : GestureDetector(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: RichText(
                        textDirection: TextDirection.rtl,
                        text: TextSpan(
                          style: DefaultTextStyle.of(context).style.copyWith(
                            color: textPrimary,
                            fontSize: 14.5,
                            height: 1.75,
                            fontWeight: FontWeight.w500,
                          ),
                          children: [
                            if (_expanded)
                              TextSpan(text: p.content)
                            else ...[
                              TextSpan(
                                text: p.content.length > 120
                                    ? p.content.substring(0, 120)
                                    : p.content,
                              ),
                              if (p.content.length > 120)
                                TextSpan(
                                  text: '... اقرأ المزيد',
                                  style: TextStyle(
                                    color: gold,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
            ),

            Divider(
                height: 20,
                thickness: 0.5,
                indent: 18,
                endIndent: 18,
                color: dividerColor),

            // ── Like + Comments Count Row ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: [
                  // Like button
                  GestureDetector(
                    onTap: _toggleLike,
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _liked
                            ? Colors.red.withOpacity(0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _liked ? Colors.red : gold.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _liked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 20,
                            color: _liked ? Colors.red : gold,
                          ),
                          if (_likesCount > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '$_likesCount',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _liked ? Colors.red : gold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Share button
                  GestureDetector(
                    onTap: () async {
                      final url = 'https://majidalbana.com/post/${widget.post.id}';
                      final text = widget.post.content.isNotEmpty
                          ? '${widget.post.content.substring(0, widget.post.content.length.clamp(0, 200))}..\n\nادخل على الرابط لقراءة المقال:\n$url'
                          : 'منشور د.ماجد البنا\n\nادخل على الرابط لقراءة المقال:\n$url';
                      await Share.share(text);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: gold.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.share_rounded, size: 16, color: gold),
                          const SizedBox(width: 6),
                          Text('مشاركة',
                              style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Comments count badge — opens bottom sheet
                  GestureDetector(
                    onTap: () {
                      _openCommentsSheet();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: gold.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: gold.withOpacity(0.35)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded,
                              size: 15, color: gold),
                          const SizedBox(width: 6),
                          Text(
                            commentCount > 0
                                ? '$commentCount ${commentCount == 1 ? 'تعليق' : 'تعليقات'}'
                                : 'تعليق',
                            style: TextStyle(
                                color: gold,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Divider(height: 1, thickness: 0.5, color: dividerColor),

            // ── Comment Input Box ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: currentUser != null
                  ? GestureDetector(
                      onTap: () {
                        _openCommentsSheet(autoFocus: true);
                      },
                      child: AbsorbPointer(
                        child: _CommentInputBox(
                          isDark: isDark,
                          user: currentUser,
                          controller: _commentCtrl,
                          sending: _sendingComment,
                          onSend: _sendComment,
                        ),
                      ),
                    )
                  : _LockedCommentBox(
                      isDark: isDark,
                      onLoginTap: _showLoginSheet,
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
// Comment Input Box (logged in)
// ─────────────────────────────────────────────────────────────────────────────

class _CommentInputBox extends StatelessWidget {
  final bool isDark;
  final User user;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final FocusNode? focusNode;

  const _CommentInputBox({
    required this.isDark,
    required this.user,
    required this.controller,
    required this.sending,
    required this.onSend,
    this.focusNode,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final fieldBg = isDark ? const Color(0xFF242424) : const Color(0xFFF5F1EA);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final hintColor = isDark ? Colors.white38 : Colors.black38;

    return Row(
      textDirection: TextDirection.rtl,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
// User Avatar (يمين)
        Padding(
          padding: const EdgeInsets.only(bottom: 2), // ← زد أو نقص هذا الرقم
          child: CircleAvatar(
            radius: 21,
            backgroundImage: user.photoURL != null
                ? NetworkImage(user.photoURL!)
                : null,
            backgroundColor: gold.withOpacity(0.2),
            child: user.photoURL == null
                ? Icon(Icons.person_rounded, color: gold, size: 18)
                : null,
          ),
        ),
        const SizedBox(width: 8),

        // Text field + send button
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 42),
            decoration: BoxDecoration(
              color: fieldBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: gold.withOpacity(0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
// Send button (يمين البوكس)
                Padding(
                  padding: const EdgeInsets.only(left: 9, right: 6, bottom: 7),
                  child: GestureDetector(
                    onTap: sending ? null : onSend,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: sending ? gold.withOpacity(0.4) : gold,
                        shape: BoxShape.circle,
                      ),
                      child: sending
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded,
                              color: Colors.white, size: 16),
                    ),
                  ),
                ),
                // Text field
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    maxLines: 4,
                    minLines: 1,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'اكتب تعليقاً...',
                      hintTextDirection: TextDirection.rtl,
                      hintStyle: TextStyle(
                          color: hintColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w400),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Locked Comment Box (not logged in)
// ─────────────────────────────────────────────────────────────────────────────

class _LockedCommentBox extends StatelessWidget {
  final bool isDark;
  final VoidCallback onLoginTap;

  const _LockedCommentBox({
    required this.isDark,
    required this.onLoginTap,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final fieldBg = isDark ? const Color(0xFF242424) : const Color(0xFFF5F1EA);
    final textSub = isDark ? Colors.white54 : Colors.black45;

    return GestureDetector(
      onTap: onLoginTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: fieldBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gold.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_rounded, size: 15, color: gold.withOpacity(0.7)),
            const SizedBox(width: 8),
            Text(
              'سجّل الدخول لترك تعليق',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  color: textSub,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: gold,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('تسجيل الدخول',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Login Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// Comments Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _CommentsBottomSheet extends StatefulWidget {
  final _PublicationPost post;
  final bool isDark;
  final List<_Comment> comments;
  final bool loadingComments;
  final bool commentsLoaded;
  final TextEditingController commentCtrl;
  final bool sendingComment;
  final VoidCallback onSend;
  final VoidCallback onLoginTap;
  final Future<void> Function() onReload;
  final Future<void> Function(int, String) onEdit;
  final Future<void> Function(int) onDelete;
  final bool autoFocus;

  const _CommentsBottomSheet({
    required this.onReload,
    required this.post,
    required this.isDark,
    required this.comments,
    required this.loadingComments,
    required this.commentsLoaded,
    required this.commentCtrl,
    required this.sendingComment,
    required this.onSend,
    required this.onLoginTap,
    required this.onEdit,
    required this.onDelete,
    this.autoFocus = false,
  });

  @override
  State<_CommentsBottomSheet> createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends State<_CommentsBottomSheet> {
  static const gold = Color(0xFFD4A017);
  final FocusNode _inputFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (!widget.commentsLoaded) widget.onReload();
    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _inputFocusNode.requestFocus();
        });
      });
    }
  }

  @override
  void dispose() {
    _inputFocusNode.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final sheetBg = isDark ? const Color(0xFF181818) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white60 : Colors.black54;
    final dividerColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.07);
    final currentUser = FirebaseAuth.instance.currentUser;
    final handleColor = isDark ? Colors.white24 : Colors.black12;

    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: DraggableScrollableSheet(
      initialChildSize: keyboardOpen ? 0.92 : 0.55,
      minChildSize: 0.35,
      maxChildSize: 1.0,
      expand: false,
      snap: true,
      snapSizes: const [0.35, 0.55, 0.92, 1.0],
      controller: DraggableScrollableController(),
      builder: (context, scrollController) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: sheetBg,
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
            children: [
              // Handle bar + Header قابل للسحب
              GestureDetector(
                onVerticalDragUpdate: (details) {
                  scrollController.position.moveTo(
                    scrollController.offset - details.delta.dy,
                    clamp: false,
                  );
                },
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Container(
                        width: 44,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: handleColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.close_rounded,
                          color: isDark ? Colors.white54 : Colors.black38,
                          size: 22),
                    ),
                    const Spacer(),
                    Text(
                      widget.comments.isNotEmpty
                          ? 'التعليقات (${widget.comments.length})'
                          : 'التعليقات',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 22),
                  ],
                ),
              ),
],
                ),
              ),

              Divider(height: 1, thickness: 0.5, color: dividerColor),

              // Comments list
              Expanded(
                child: widget.loadingComments
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: gold, strokeWidth: 2.5))
                    : widget.comments.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.chat_bubble_outline_rounded,
                                    size: 44,
                                    color: gold.withOpacity(0.4)),
                                const SizedBox(height: 12),
                                Text(
                                  'لا توجد تعليقات بعد\nكن أول من يعلّق!',
                                  textAlign: TextAlign.center,
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(
                                      color: textSub,
                                      fontSize: 14,
                                      height: 1.7),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            itemCount: widget.comments.length,
                           separatorBuilder: (_, __) =>
                                Divider(height: 28, color: isDark ? Color.fromARGB(1, 49, 49, 49).withOpacity(0.05) : Color.fromARGB(6, 190, 190, 190).withOpacity(0.06)),
                            itemBuilder: (context, i) {
                              final c = widget.comments[i];
                              if (c.text.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return _CommentTile(
                                comment: c,
                                isDark: isDark,
                                onEdit: widget.onEdit,
                                onDelete: widget.onDelete,
                              );
                            },
                          ),
              ),

              // Input box
              Divider(height: 1, thickness: 0.5, color: dividerColor),
              Padding(
                padding: EdgeInsets.fromLTRB(
                    12,
                    10,
                    12,
                    10 + MediaQuery.of(context).viewInsets.bottom),
                child: currentUser != null
                    ? _CommentInputBox(
                        isDark: isDark,
                        user: currentUser,
                        controller: widget.commentCtrl,
                        sending: widget.sendingComment,
                        focusNode: _inputFocusNode,
                        onSend: () {
                          widget.onSend();
                          setState(() {});
                        },
                      )
                    : _LockedCommentBox(
                        isDark: isDark,
                        onLoginTap: widget.onLoginTap,
                      ),
              ),
            ],
          ),
        );
      },
    ),
    ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Comment Tile (used inside sheet)
// ─────────────────────────────────────────────────────────────────────────────

class _CommentTile extends StatefulWidget {
  final _Comment comment;
  final bool isDark;
  final Future<void> Function(int, String)? onEdit;
  final Future<void> Function(int)? onDelete;

  const _CommentTile({
    required this.comment,
    required this.isDark,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  static const gold = Color(0xFFD4A017);
  bool _editing = false;
  late TextEditingController _editCtrl;

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController(text: widget.comment.text);
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  bool get _isOwner {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    return user.displayName == widget.comment.userName ||
        user.email == widget.comment.userName;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white54 : Colors.black45;
    final fieldBg = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0EBE0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      textDirection: TextDirection.rtl,
      children: [
        // Avatar
        CircleAvatar(
          radius: 18,
          backgroundColor: gold.withOpacity(0.18),
          backgroundImage: widget.comment.userAvatar.isNotEmpty
              ? NetworkImage(widget.comment.userAvatar)
              : null,
          child: widget.comment.userAvatar.isEmpty
              ? Icon(Icons.person_rounded, color: gold, size: 18)
              : null,
        ),
        const SizedBox(width: 10),

        // Name + time + comment text + actions
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Name + time
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Text(
                    widget.comment.userName,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: isDark
                          ? const Color.fromARGB(253, 177, 171, 155)
                          : const Color(0xFF8B5E00),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.comment.timeAgo.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      widget.comment.timeAgo,
                      style: TextStyle(color: textSub, fontSize: 11),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),

              // Comment text أو حقل التعديل
              _editing
                  ? Container(
                      decoration: BoxDecoration(
                        color: fieldBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: gold.withOpacity(0.3)),
                      ),
                      child: TextField(
                        controller: _editCtrl,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        maxLines: 4,
                        minLines: 1,
                        style: TextStyle(color: textPrimary, fontSize: 13.5),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          border: InputBorder.none,
                        ),
                      ),
                    )
                  : Text(
                      widget.comment.text,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 13.5,
                        height: 1.6,
                      ),
                    ),

              // أزرار التعديل والحذف (فقط لصاحب التعليق)
              if (_isOwner) ...[
                const SizedBox(height: 6),
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    if (_editing) ...[
                      GestureDetector(
                        onTap: () async {
                          final newText = _editCtrl.text.trim();
                          if (newText.isEmpty) return;
                          debugPrint('### SAVE TAPPED id=${widget.comment.id} newText=$newText ###');
                          if (widget.onEdit != null) {
                            await widget.onEdit!(widget.comment.id, newText);
                          }
                          if (mounted) setState(() => _editing = false);
                        },
                        child: Text(
                          'حفظ',
                          style: TextStyle(
                              color: gold,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          _editCtrl.text = widget.comment.text;
                          setState(() => _editing = false);
                        },
                        child: Text(
                          'إلغاء',
                          style: TextStyle(
                              color: textSub,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ] else ...[
                      GestureDetector(
                        onTap: () => setState(() => _editing = true),
                        child: Text(
                          'تعديل',
                          style: TextStyle(
                              color: gold,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              backgroundColor: isDark
                                  ? const Color(0xFF222222)
                                  : Colors.white,
                              title: Text('حذف التعليق',
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(color: textPrimary)),
                              content: Text('هل أنت متأكد من حذف التعليق؟',
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(color: textSub)),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text('إلغاء',
                                      style: TextStyle(color: textSub)),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text('حذف',
                                      style:
                                          TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await widget.onDelete
                                ?.call(widget.comment.id);
                          }
                        },
                        child: const Text(
                          'حذف',
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
class _LoginSheet extends StatefulWidget {
  final bool isDark;
  final VoidCallback onLoggedIn;

  const _LoginSheet({required this.isDark, required this.onLoggedIn});

  @override
  State<_LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<_LoginSheet> {
  static const gold = Color(0xFFD4A017);
  bool _loading = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _loading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (mounted) widget.onLoggedIn();
    } catch (e) {
      setState(() {
        _error = 'فشل تسجيل الدخول. حاول مرة أخرى.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final sheetBg = isDark ? const Color(0xFF181818) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white60 : Colors.black54;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 20),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: gold.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),

                // Icon
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [gold.withOpacity(0.3), gold.withOpacity(0.1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chat_bubble_rounded,
                      color: gold, size: 32),
                ),
                const SizedBox(height: 16),

                Text(
                  'سجّل الدخول للتعليق',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'انضم إلى النقاش واترك تعليقك\nعلى منشورات د.ماجد البنا',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textSub,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 28),

                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 13)),
                  ),
                  const SizedBox(height: 16),
                ],

                // Google Sign In Button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _signInWithGoogle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isDark ? const Color(0xFF2A2A2A) : Colors.white,
                      foregroundColor: textPrimary,
                      elevation: 0,
                      side: BorderSide(
                          color: isDark
                              ? Colors.white12
                              : Colors.black12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _loading
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                color: gold, strokeWidth: 2.5))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Google logo
                              Container(
                                width: 24,
                                height: 24,
                                decoration: const BoxDecoration(
                                  image: DecorationImage(
                                    image: NetworkImage(
                                        'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg'),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'تسجيل الدخول بـ Google',
                                    textDirection: TextDirection.rtl,
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Transform.translate(
                                    offset: const Offset(0, -2), // ← غيّر الأرقام: (يمين/يسار, أعلى/أسفل)
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(4),
                                      child: SvgPicture.network(
                                        'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                                        width: 20,
                                        height: 20,
                                      ),
                                    ),
                                  ),
                                ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Post Detail Page (Full Post + Comments)
// ─────────────────────────────────────────────────────────────────────────────

class _PostDetailPage extends StatefulWidget {
  final _PublicationPost post;
  final bool isDark;
  final VideoPlayerController? existingController;

  const _PostDetailPage({
    required this.post,
    required this.isDark,
    this.existingController,
  });

  @override
  State<_PostDetailPage> createState() => _PostDetailPageState();
}
class _ExistingVideoPlayer extends StatefulWidget {
  final VideoPlayerController controller;
  final bool isDark;

  const _ExistingVideoPlayer({
    required this.controller,
    required this.isDark,
  });

  @override
  State<_ExistingVideoPlayer> createState() => _ExistingVideoPlayerState();
}

class _ExistingVideoPlayerState extends State<_ExistingVideoPlayer> {
  static const gold = Color(0xFFD4A017);
  bool _muted = false;
  bool _isDraggingSlider = false;

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    return AspectRatio(
      aspectRatio: ctrl.value.aspectRatio,
      child: Stack(
        children: [
          Positioned.fill(child: VideoPlayer(ctrl)),

          // أزرار الكتم والتشغيل
          Positioned(
            top: 8,
            left: 10,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _muted = !_muted;
                      ctrl.setVolume(_muted ? 0 : 1.0);
                    });
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: ctrl,
                  builder: (_, value, __) => GestureDetector(
                    onTap: () => setState(() {
                      value.isPlaying ? ctrl.pause() : ctrl.play();
                    }),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // شريط التمرير
          Positioned(
            left: 0,
            right: 0,
            bottom: -9.5,
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: ctrl,
              builder: (_, value, __) {
                if (!value.isInitialized) return const SizedBox();
                final dur = value.duration.inMilliseconds.toDouble();
                final safeMax = dur > 1 ? dur : 1.0;
                final pos = value.position.inMilliseconds.toDouble().clamp(0.0, safeMax);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isDraggingSlider)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(value.duration),
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                            Text(_fmt(value.position),
                                style: const TextStyle(color: Color.fromARGB(255, 255, 255, 255), fontSize: 11, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: _isDraggingSlider ? 3.5 : 2.5,
                        trackShape: const RectangularSliderTrackShape(),
                        thumbShape: RoundSliderThumbShape(enabledThumbRadius: _isDraggingSlider ? 7 : 5),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: const Color.fromARGB(255, 255, 255, 255),
                        inactiveTrackColor: Colors.white30,
                        thumbColor: const Color.fromARGB(255, 255, 255, 255),
                        overlayColor: const Color.fromARGB(255, 255, 255, 255).withOpacity(0.25),
                      ),
                      child: Directionality(
                        textDirection: TextDirection.rtl,
                       child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: SizedBox(
                          height: 20,
                          child: Slider(
                            value: pos,
                            min: 0,
                            max: safeMax,
                            onChangeStart: (_) {
                              ctrl.pause();
                              setState(() => _isDraggingSlider = true);
                            },
                            onChanged: (v) => ctrl.seekTo(Duration(milliseconds: v.toInt())),
                            onChangeEnd: (_) {
                              ctrl.play();
                              setState(() => _isDraggingSlider = false);
                            },
                          ),
                        ),
                      ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
class _PostDetailPageState extends State<_PostDetailPage> {
  static const gold = Color(0xFFD4A017);
  static const String _commentsApi =
      'https://majidalbana.com/admin/comments/load_comments.php';
  static const String _addCommentApi =
      'https://majidalbana.com/admin/comments/add_comment.php';
  static const String _editCommentApi =
      'https://majidalbana.com/admin/comments/edit_comment.php';
  static const String _deleteCommentApi =
      'https://majidalbana.com/admin/comments/delete_comment.php';
  static const String _toggleLikeApi =
      'https://majidalbana.com/admin/posts/toggle_like.php';
  static const String _getLikesApi =
      'https://majidalbana.com/admin/posts/get_likes.php';

  List<_Comment> _comments = [];
  bool _loadingComments = true;
  bool _commentsLoaded = false;
  bool _sendingComment = false;
  final _commentCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _liked = false;
  int _likesCount = 0;
  bool _likeLoading = false;
  VideoPlayerController? _videoController;
  bool _videoOwned = false;
  Timer? _refreshTimer;

  String get _cacheKey => 'post_detail_${widget.post.id}';

  @override
  void initState() {
    super.initState();
    _loadFromCacheThenNetwork();
    if (widget.existingController != null) {
      _videoController = widget.existingController;
      _videoOwned = false;
    }
    // تحقق كل 5 دقائق من وجود تحديثات
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _silentRefresh();
    });
  }

  // تحميل من الكاش أولاً ثم تحديث من الشبكة
  Future<void> _loadFromCacheThenNetwork() async {
    await _loadFromCache();
    await _fetchFromNetwork();
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _liked = data['liked'] == true;
        _likesCount = (data['likes_count'] as num?)?.toInt() ?? 0;
        final rawComments = data['comments'];
        if (rawComments is List) {
          _comments = rawComments
              .whereType<Map>()
              .map((e) => _Comment.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          _commentsLoaded = true;
          _loadingComments = false;
        }
      });
    } catch (_) {}
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'liked': _liked,
        'likes_count': _likesCount,
        'comments': _comments.map((c) => c.toJson()).toList(),
      };
      await prefs.setString(_cacheKey, jsonEncode(data));
    } catch (_) {}
  }

  // تحميل من الشبكة وتحديث الـ UI إن وجد تغيير
  Future<void> _fetchFromNetwork() async {
    await Future.wait([_loadComments(), _loadLikes()]);
  }

  // تحديث صامت كل 5 دقائق — بدون loading indicator
  Future<void> _silentRefresh() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email ?? '';

      // تحديث الإعجابات
      final likeUri = Uri.parse(_getLikesApi).replace(queryParameters: {
        'post_id': '${widget.post.id}',
        if (email.isNotEmpty) 'user_email': email,
      });
      final likeRes = await http.get(likeUri).timeout(const Duration(seconds: 10));
      if (likeRes.statusCode == 200 && mounted) {
        final likeData = jsonDecode(utf8.decode(likeRes.bodyBytes));
        if (likeData is Map && likeData['success'] == true) {
          final newLiked = likeData['liked'] == true;
          final newCount = int.tryParse('${likeData['likes_count'] ?? _likesCount}') ?? _likesCount;
          if (newLiked != _liked || newCount != _likesCount) {
            setState(() {
              _liked = newLiked;
              _likesCount = newCount;
            });
          }
        }
      }

      // تحديث التعليقات
      final commentsRes = await http.get(
        Uri.parse('$_commentsApi?post_id=${widget.post.id}'),
      ).timeout(const Duration(seconds: 10));
      if (commentsRes.statusCode == 200 && mounted) {
        final commentsData = jsonDecode(utf8.decode(commentsRes.bodyBytes));
        if (commentsData is List) {
          final fresh = commentsData
              .whereType<Map>()
              .map((e) => _Comment.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          // تحقق إذا في تغيير قبل تحديث الـ UI
          final changed = fresh.length != _comments.length ||
              fresh.any((c) {
                final old = _comments.firstWhere(
                  (o) => o.id == c.id,
                  orElse: () => _Comment(
                    id: -1, postId: 0, userName: '', userAvatar: '', text: '', createdAt: ''),
                );
                return old.id == -1 || old.text != c.text;
              });
          if (changed && mounted) {
            setState(() => _comments = fresh);
            await _saveToCache();
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadLikes() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email ?? '';
      final uri = Uri.parse(_getLikesApi).replace(queryParameters: {
        'post_id': '${widget.post.id}',
        if (email.isNotEmpty) 'user_email': email,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is Map && data['success'] == true) {
          setState(() {
            _likesCount = int.tryParse('${data['likes_count'] ?? 0}') ?? 0;
            _liked = data['liked'] == true;
          });
          await _saveToCache();
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (_likeLoading) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || (user.email ?? '').isEmpty) {
      _showLoginSheet();
      return;
    }

    setState(() {
      _likeLoading = true;
      if (_liked) {
        _liked = false;
        _likesCount = (_likesCount - 1).clamp(0, 1 << 31);
      } else {
        _liked = true;
        _likesCount += 1;
      }
    });

    try {
      final res = await http.post(
        Uri.parse(_toggleLikeApi),
        body: {
          'post_id': '${widget.post.id}',
          'user_email': user.email ?? '',
        },
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is Map && data['success'] == true) {
          setState(() {
            _liked = data['liked'] == true;
            _likesCount =
                int.tryParse('${data['likes_count'] ?? _likesCount}') ??
                    _likesCount;
          });
        } else {
          await _loadLikes();
        }
      } else {
        await _loadLikes();
      }
    } catch (_) {
      if (mounted) await _loadLikes();
    } finally {
      if (mounted) setState(() => _likeLoading = false);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    if (_videoOwned) _videoController?.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    if (!_commentsLoaded) setState(() => _loadingComments = true);
    try {
      final res = await http.get(
        Uri.parse('$_commentsApi?post_id=${widget.post.id}'),
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is List) {
          setState(() {
            _comments = data
                .whereType<Map>()
                .map((e) => _Comment.fromJson(Map<String, dynamic>.from(e)))
                .toList();
            _commentsLoaded = true;
          });
          await _saveToCache();
        }
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _sendingComment = true);
    try {
      final res = await http.post(
        Uri.parse(_addCommentApi),
        body: {
          'post_id': '${widget.post.id}',
          'user_name': user.displayName ?? 'مستخدم',
          'user_avatar': user.photoURL ?? '',
          'comment_text': text,
          'user_email': user.email ?? '',
        },
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      // DEBUG — شيل هذا بعد ما تحل المشكلة
      print('=== DEBUG COMMENT ===');
      print('post_id: ${widget.post.id}');
      print('user: ${user.displayName}');
      print('status: ${res.statusCode}');
      print('response: ${utf8.decode(res.bodyBytes)}');
      print('====================');

if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data['success'] == true) {
          _commentCtrl.clear();
          await _loadComments();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('تم إرسال التعليق بنجاح ✓',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontWeight: FontWeight.w600)),
              backgroundColor: const Color(0xFF2E7D32),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              margin: const EdgeInsets.all(14),
            ));
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                'فشل إرسال التعليق: ${data['error'] ?? 'خطأ غير معروف'}',
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              margin: const EdgeInsets.all(14),
            ));
          }
        }
      }
    } catch (e) {
      print('ERROR: $e');
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }
Future<void> _editComment(int commentId, String newText) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final res = await http.post(
        Uri.parse(_editCommentApi),
        body: {
          'comment_id': '$commentId',
          'comment_text': newText,
          'user_email': user.email ?? '',
        },
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data['success'] == true) {
          await _loadComments();
        }
      }
    } catch (_) {}
  }

  Future<void> _deleteComment(int commentId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final res = await http.post(
        Uri.parse(_deleteCommentApi),
        body: {
          'comment_id': '$commentId',
          'user_email': user.email ?? '',
        },
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data['success'] == true) {
          await _loadComments();
        }
      }
    } catch (_) {}
  }
  void _showLoginSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LoginSheet(
        isDark: widget.isDark,
        onLoggedIn: () {
          setState(() {});
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final p = widget.post;
    final bgColor =
        isDark ? const Color(0xFF101010) : const Color(0xFFF7F4EE);
    final cardBg = isDark ? const Color(0xFF181818) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white60 : Colors.black54;
    final dividerColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.07);
    final currentUser = FirebaseAuth.instance.currentUser;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null &&
            details.primaryVelocity!.abs() > 300) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF181818) : Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'المنشور',
          style: TextStyle(
            color: textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: gold.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                color: gold, size: 18),
          ),
        ),
        actions: [
          GestureDetector(
            onTap: () async {
              final url = 'https://majidalbana.com/post/${p.id}';
              final text = p.content.isNotEmpty
                  ? '${p.content.substring(0, p.content.length.clamp(0, 200))}..\n\nادخل على الرابط لقراءة المقال:\n$url'
                  : 'منشور د.ماجد البنا\n\nادخل على الرابط لقراءة المقال:\n$url';
              await Share.share(text);
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: gold.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: gold.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.share_rounded, size: 16, color: gold),
                  const SizedBox(width: 6),
                  Text('مشاركة',
                      style: TextStyle(
                          color: textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: dividerColor),
        ),
      ),
      body: Column(
        children: [
          // ── Scrollable content ─────────────────────────────────────────
          Expanded(
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                // Post Image / Video
if (p.videoUrl != null)
              _videoController != null
                  ? _ExistingVideoPlayer(
                      controller: _videoController!,
                      isDark: widget.isDark,
                    )
                  : _PostVideoPlayer(
                      videoUrl: p.videoUrl!,
                      isDark: widget.isDark,
                      post: p,
                    )
                else if (p.imageUrls.isNotEmpty)
                  _PostImageGallery(imageUrls: p.imageUrls, isDark: isDark),

                // Post Content Card
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: gold.withOpacity(0.12)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.15 : 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Author
    Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundImage:
                                const AssetImage('assets/images/majid.png'),
                            backgroundColor: gold.withOpacity(0.15),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                  'د.ماجد البنا',
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                              Row(
                                textDirection: TextDirection.rtl,
                                children: [
                                  Icon(Icons.calendar_month_rounded,
                                      size: 12, color: textSub),
                                  const SizedBox(width: 4),
                                  Text(p.formattedDate,
                                      style: TextStyle(
                                          color: textSub, fontSize: 11.5)),
                                ],
                              ),
                            ],
                          ),
                          const Spacer(),
                          // Like button
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _toggleLike();
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              child: Row(
                                children: [
                                  AnimatedScale(
                                    scale: _liked ? 1.2 : 1.0,
                                    duration: const Duration(milliseconds: 150),
                                    curve: Curves.elasticOut,
                                    child: Icon(
                                      _liked
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      size: 24,
                                      color: _liked ? Colors.red : gold,
                                    ),
                                  ),
                                  if (_likesCount > 0) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '$_likesCount',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _liked ? Colors.red : gold,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (p.content.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Divider(height: 1, color: dividerColor),
                        const SizedBox(height: 14),
                        Text(
                          p.content,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 15,
                            height: 1.85,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ── Comments Section ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Row(
                    textDirection: TextDirection.rtl,
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
                        'التعليقات${_comments.isNotEmpty ? ' (${_comments.length})' : ''}',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      if (_loadingComments)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: gold, strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
                        const SizedBox(height: 14),

                if (!_loadingComments && _comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded,
                            color: gold.withOpacity(0.4), size: 42),
                        const SizedBox(height: 10),
                        Text(
                          'كن أول من يعلّق!',
                          style: TextStyle(
                              color: textSub,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),

                ..._comments
                    .where((c) => c.text.isNotEmpty)
                    .map((c) => Column(
                          children: [
                            _CommentBubble(
                              comment: c,
                              isDark: isDark,
                              onEdit: _editComment,
                              onDelete: _deleteComment,
                            ),
                            Divider(
                              height: 1,
                              thickness: 0.5,
                              indent: 16,
                              endIndent: 16,
                              color: isDark
                                  ? Colors.white.withOpacity(0.06)
                                  : Colors.black.withOpacity(0.06),
                            ),
                          ],
                        )),
                        
              ],
            ),
          ),

          // ── Fixed bottom comment input ─────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(
                12, 10, 12, MediaQuery.of(context).padding.bottom + 10),
            decoration: BoxDecoration(
              color: cardBg,
              border: Border(
                  top: BorderSide(color: dividerColor, width: 0.8)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: currentUser != null
                ? _CommentInputBox(
                    isDark: isDark,
                    user: currentUser,
                    controller: _commentCtrl,
                    sending: _sendingComment,
                    onSend: _sendComment,
                  )
                : _LockedCommentBox(
                    isDark: isDark,
                    onLoginTap: _showLoginSheet,
                  ),
          ),
        ],
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Comment Bubble
// ─────────────────────────────────────────────────────────────────────────────

class _CommentBubble extends StatefulWidget {
  final _Comment comment;
  final bool isDark;
  final Future<void> Function(int, String)? onEdit;
  final Future<void> Function(int)? onDelete;

  const _CommentBubble({
    required this.comment,
    required this.isDark,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<_CommentBubble> createState() => _CommentBubbleState();
}

class _CommentBubbleState extends State<_CommentBubble> {
  static const gold = Color(0xFFD4A017);
  bool _editing = false;
  late TextEditingController _editCtrl;

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController(text: widget.comment.text);
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  bool get _isOwner {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    return user.displayName == widget.comment.userName ||
        user.email == widget.comment.userName;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bubbleBg = isDark ? const Color(0xFF222222) : const Color(0xFFFAF6EF);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white54 : Colors.black45;
    final fieldBg = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0EBE0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: TextDirection.rtl,
        children: [
          // Avatar (يمين)
          CircleAvatar(
            radius: 19,
            backgroundImage: widget.comment.userAvatar.isNotEmpty
                ? NetworkImage(widget.comment.userAvatar)
                : null,
            backgroundColor: gold.withOpacity(0.2),
            child: widget.comment.userAvatar.isEmpty
                ? Text(
                    widget.comment.userName.isNotEmpty
                        ? widget.comment.userName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        color: gold,
                        fontWeight: FontWeight.w800,
                        fontSize: 15),
                  )
                : null,
          ),
          const SizedBox(width: 10),

          // Bubble
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        widget.comment.userName,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: const Color.fromARGB(255, 82, 106, 143),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _editing
                          ? Container(
                              decoration: BoxDecoration(
                                color: fieldBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: gold.withOpacity(0.3)),
                              ),
                              child: TextField(
                                controller: _editCtrl,
                                textDirection: TextDirection.rtl,
                                textAlign: TextAlign.right,
                                maxLines: 4,
                                minLines: 1,
                                style: TextStyle(color: textPrimary, fontSize: 13.5),
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: InputBorder.none,
                                ),
                              ),
                            )
                          : Text(
                              widget.comment.text,
                              textDirection: TextDirection.rtl,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 13.5,
                                height: 1.55,
                              ),
                            ),
                    ],
                  ),
                if (_isOwner) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    
                    children: [
                      
                      if (_editing) ...[                      
                        GestureDetector(
                          onTap: () async {
                            final newText = _editCtrl.text.trim();
                            if (newText.isEmpty) return;
                            await widget.onEdit?.call(widget.comment.id, newText);
                            if (mounted) setState(() => _editing = false);
                          },
                          child: Icon(Icons.check_circle_rounded, color: gold, size: 20),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () {
                            _editCtrl.text = widget.comment.text;
                            setState(() => _editing = false);
                          },
                          child: Icon(Icons.cancel_rounded, color: textSub, size: 20),
                        ),
                      ] else ...[
                        GestureDetector(
                          onTap: () => setState(() => _editing = true),
                          child: Icon(Icons.edit_rounded, color: const Color.fromARGB(255, 104, 107, 109), size: 17),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                backgroundColor: isDark ? const Color(0xFF222222) : Colors.white,
                                title: Text('حذف التعليق', textDirection: TextDirection.rtl, style: TextStyle(color: textPrimary)),
                                content: Text('هل أنت متأكد من حذف التعليق؟', textDirection: TextDirection.rtl, style: TextStyle(color: textSub)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: Text('إلغاء', style: TextStyle(color: textSub))),
                                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
                                ],
                              ),
                            );
                            if (confirm == true) await widget.onDelete?.call(widget.comment.id);
                          },
                          child: Icon(Icons.delete_rounded, color: const Color.fromARGB(255, 99, 86, 85), size: 17),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    widget.comment.timeAgo,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(color: textSub, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Post Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _EditPostSheet extends StatefulWidget {
  final _PublicationPost post;
  final bool isDark;
  final void Function(_PublicationPost) onSaved;

  const _EditPostSheet({
    required this.post,
    required this.isDark,
    required this.onSaved,
  });

  @override
  State<_EditPostSheet> createState() => _EditPostSheetState();
}

class _EditPostSheetState extends State<_EditPostSheet> {
  static const gold = Color(0xFFD4A017);
  static const String _updateApi =
      'https://majidalbana.com/admin/posts/update_post.php';

  late TextEditingController _contentCtrl;
  File? _newImage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _contentCtrl = TextEditingController(text: widget.post.content);
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _newImage = File(picked.path));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final request =
          http.MultipartRequest('POST', Uri.parse(_updateApi));
      request.fields['id'] = '${widget.post.id}';
      request.fields['content'] = _contentCtrl.text.trim();
      if (_newImage != null) {
        request.files.add(
          await http.MultipartFile.fromPath('image', _newImage!.path),
        );
      }
      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
      final body = await streamed.stream.bytesToString();
      final json = jsonDecode(body);
      if (json['success'] == true) {
        final updated = widget.post.copyWith(
          content: _contentCtrl.text.trim(),
          image: _newImage != null
              ? _newImage!.path.split('/').last
              : null,
        );
        widget.onSaved(updated);
        if (mounted) Navigator.pop(context);
        _showSnack('تم التعديل بنجاح ✓', success: true);
      } else {
        _showSnack('فشل التعديل');
        setState(() => _saving = false);
      }
    } catch (_) {
      _showSnack('خطأ في الاتصال');
      setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'حذف المنشور',
          textDirection: TextDirection.rtl,
          style: TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        content: const Text(
          'هل أنت متأكد من حذف هذا المنشور؟\nلا يمكن التراجع عن هذه العملية.',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء',
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('حذف', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final response = await http.post(
        Uri.parse('https://majidalbana.com/admin/posts/delete_post.php'),
        body: {'id': '${widget.post.id}'},
      ).timeout(const Duration(seconds: 20));
      final json = jsonDecode(response.body);
      if (json['success'] == true) {
        if (mounted) Navigator.pop(context, 'deleted');
      } else {
        _showSnack('فشل الحذف. حاول مجدداً');
        setState(() => _saving = false);
      }
    } catch (_) {
      _showSnack('خطأ في الاتصال');
      setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool success = false}) {
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor:
          success ? const Color(0xFF2E7D32) : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(14),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final sheetBg = isDark ? const Color(0xFF181818) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final hintColor = isDark ? Colors.white38 : Colors.black38;
    final fieldBg =
        isDark ? const Color(0xFF232323) : const Color(0xFFFAF6EF);
    final borderColor = gold.withOpacity(0.35);

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: gold.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(Icons.edit_rounded,
                          color: gold, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'تعديل المنشور',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: fieldBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _newImage != null
                                ? Image.file(_newImage!,
                                    fit: BoxFit.cover)
                                : (widget.post.image.isNotEmpty
                                    ? Image.network(
                                        widget.post.imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            Icon(
                                              Icons.broken_image_outlined,
                                              color: Colors.black38,
                                              size: 42,
                                            ),
                                      )
                                    : Center(
                                        child: Icon(
                                          Icons.image_outlined,
                                          color: gold.withOpacity(0.4),
                                          size: 42,
                                        ),
                                      )),
                            Positioned(
                              bottom: 10,
                              left: 10,
                              child: GestureDetector(
                                onTap: _pickImage,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.65),
                                    borderRadius:
                                        BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.swap_horiz_rounded,
                                          color: Colors.white, size: 15),
                                      SizedBox(width: 6),
                                      Text('تغيير الصورة',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (_newImage != null)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: gold.withOpacity(0.85),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: const Text('صورة جديدة',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: fieldBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                      ),
                      child: TextField(
                        controller: _contentCtrl,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        maxLines: 6,
                        minLines: 3,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 14.5,
                          height: 1.7,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'وصف المنشور...',
                          hintTextDirection: TextDirection.rtl,
                          hintStyle: TextStyle(
                              color: hintColor,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w400),
                          contentPadding: const EdgeInsets.all(14),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _saving ? null : _save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: gold,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: gold.withOpacity(0.5),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.check_rounded, size: 19),
                                        SizedBox(width: 8),
                                        Text('حفظ التعديلات',
                                            style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800)),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 50,
                          width: 50,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _delete,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.red.withOpacity(0.4),
                              elevation: 0,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Icon(Icons.delete_rounded, size: 22),
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
    );
  }
}



class _VideoControllerProvider extends InheritedWidget {
  final VideoPlayerController controller;

  const _VideoControllerProvider({
    required this.controller,
    required super.child,
  });

  static _VideoControllerProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_VideoControllerProvider>();
  }

  @override
  bool updateShouldNotify(_VideoControllerProvider old) =>
      controller != old.controller;
}
// ─────────────────────────────────────────────────────────────────────────────
// Post Video Player — تلقائي، بدون أزرار تشغيل/إيقاف، مع شريط تمرير وكتم
// ─────────────────────────────────────────────────────────────────────────────

class _PostVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool isDark;
  final _PublicationPost post;

  const _PostVideoPlayer({
    required this.videoUrl,
    required this.isDark,
    required this.post,
  });

  @override
  State<_PostVideoPlayer> createState() => _PostVideoPlayerState();
}
class _VideoFullPage extends StatefulWidget {
  final VideoPlayerController controller;
  final bool isDark;
  final VoidCallback onReturn;

  const _VideoFullPage({
    required this.controller,
    required this.isDark,
    required this.onReturn,
  });

  @override
  State<_VideoFullPage> createState() => _VideoFullPageState();
}

class _VideoFullPageState extends State<_VideoFullPage> {
  static const gold = Color(0xFFD4A017);
  bool _muted = false;
  bool _isDraggingSlider = false;

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    widget.onReturn();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // الفيديو في المنتصف
            Center(
              child: AspectRatio(
                aspectRatio: ctrl.value.aspectRatio,
                child: VideoPlayer(ctrl),
              ),
            ),

            // زر الرجوع
            Positioned(
              top: 8,
              right: 12,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ),

            // أزرار الكتم والتشغيل
            Positioned(
              top: 8,
              left: 10,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _muted = !_muted;
                        ctrl.setVolume(_muted ? 0 : 1.0);
                      });
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: ctrl,
                    builder: (_, value, __) {
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            value.isPlaying ? ctrl.pause() : ctrl.play();
                          });
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // شريط التمرير في الأسفل
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: ctrl,
                builder: (_, value, __) {
                  if (!value.isInitialized) return const SizedBox();
                  final dur = value.duration.inMilliseconds.toDouble();
                  final safeMax = dur > 1 ? dur : 1.0;
                  final pos = value.position.inMilliseconds
                      .toDouble()
                      .clamp(0.0, safeMax);

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isDraggingSlider)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_fmt(value.duration),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                              Text(_fmt(value.position),
                                  style: const TextStyle(
                                      color: gold,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: _isDraggingSlider ? 3.5 : 2.5,
                          trackShape: const RectangularSliderTrackShape(),
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: _isDraggingSlider ? 7 : 5,
                          ),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          activeTrackColor: gold,
                          inactiveTrackColor: Colors.white30,
                          thumbColor: gold,
                          overlayColor: gold.withOpacity(0.25),
                        ),
                        child: SizedBox(
                          height: 20,
                          child: Slider(
                            value: pos,
                            min: 0,
                            max: safeMax,
                            onChangeStart: (_) {
                              ctrl.pause();
                              setState(() => _isDraggingSlider = true);
                            },
                            onChanged: (v) => ctrl.seekTo(
                                Duration(milliseconds: v.toInt())),
                            onChangeEnd: (_) {
                              ctrl.play();
                              setState(() => _isDraggingSlider = false);
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _PostVideoPlayerState extends State<_PostVideoPlayer>
    with AutomaticKeepAliveClientMixin {
  static const gold = Color(0xFFD4A017);
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _muted = false;
  bool _showControls = true;
  bool _disposed = false;
  bool _isDraggingSlider = false;
  bool _isTransferred = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final ctrl = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    try {
      await ctrl.initialize();
    } catch (e) {
      debugPrint('Video init error: $e');
      ctrl.dispose();
      return;
    }
    // تحقق بعد await — هل الـ widget لا يزال موجوداً؟
    if (!mounted) {
      ctrl.dispose();
      return;
    }
    await ctrl.setLooping(true);
    await ctrl.setVolume(1.0);
    await ctrl.play();
    setState(() {
      _controller = ctrl;
      _initialized = true;
    });
    _scheduleHideControls();
  }

  void _scheduleHideControls() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_disposed) setState(() => _showControls = false);
    });
  }

@override
  void dispose() {
    _disposed = true;
    if (!_isTransferred) _controller?.dispose();
    super.dispose();
  }

  void _toggleMute() {
    if (_controller == null) return;
    setState(() {
      _muted = !_muted;
      _controller!.setVolume(_muted ? 0 : 1.0);
    });
  }

  void _onTapVideo() {
    setState(() => _showControls = true);
    _scheduleHideControls();
  }
String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_initialized || _controller == null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: widget.isDark ? const Color(0xFF222222) : const Color(0xFFEFE7D8),
          child: const Center(
            child: CircularProgressIndicator(color: gold, strokeWidth: 2.5),
          ),
        ),
      );
    }

return VisibilityDetector(
      key: Key('video_${widget.videoUrl}'),
      onVisibilityChanged: (info) {
        if (!mounted || _controller == null || _isTransferred) return;
        if (info.visibleFraction > 0.6) {
          if (!_controller!.value.isPlaying) _controller!.play();
        } else {
          if (_controller!.value.isPlaying) _controller!.pause();
        }
      },
      child: GestureDetector(
        onTap: () {
          if (_controller == null) return;
          setState(() => _isTransferred = true);
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (_, animation, __) => FadeTransition(
                opacity: animation,
                child: _PostDetailPage(
                  post: widget.post,
                  isDark: widget.isDark,
                  existingController: _controller,
                ),
              ),
              transitionDuration: const Duration(milliseconds: 300),
            ),
          ).then((_) {
            if (mounted) setState(() => _isTransferred = false);
          });
        },
        behavior: HitTestBehavior.opaque,
        child: AspectRatio(
          aspectRatio: _controller!.value.aspectRatio,
        child: Stack(
          children: [
            // الفيديو
            Positioned.fill(child: VideoPlayer(_controller!)),

            // زر الكتم — دائماً ظاهر في أعلى اليسار
// أزرار الكتم والتشغيل — دائماً ظاهرة في أعلى اليسار
            Positioned(
              top: 5,
              left: 5,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _toggleMute,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: const Color.fromARGB(199, 255, 255, 255),
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      if (_controller == null) return;
                      setState(() {
                        _controller!.value.isPlaying
                            ? _controller!.pause()
                            : _controller!.play();
                      });
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _controller!.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: const Color.fromARGB(199, 255, 255, 255),
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // شريط التمرير في أسفل الفيديو تماماً مع عرض الوقت عند السحب
            Positioned(
              left: 0,
              right: 0,
              bottom: -9,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _controller!,
                builder: (_, value, __) {
                  if (!value.isInitialized) return const SizedBox();
                  final dur = value.duration.inMilliseconds.toDouble();
                  final safeMax = dur > 1 ? dur : 1.0;
                  final pos = value.position.inMilliseconds
                      .toDouble()
                      .clamp(0.0, safeMax);

        
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // عرض الوقت فقط أثناء السحب
                      if (_isDraggingSlider)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _fmt(value.duration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                _fmt(value.position),
                                style: const TextStyle(
                                  color: const Color.fromARGB(255, 255, 255, 255),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: _isDraggingSlider ? 3.5 : 2.5,
                          trackShape: const RectangularSliderTrackShape(),
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: _isDraggingSlider ? 7 : 5,
                          ),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          activeTrackColor: const Color.fromARGB(255, 255, 255, 255),
                          inactiveTrackColor: Colors.white30,
                          thumbColor: const Color.fromARGB(255, 255, 255, 255),
                          overlayColor: const Color.fromARGB(255, 255, 255, 255).withOpacity(0.25),
                        ),
                        child: SizedBox(
                          height: 20,
                          child: Slider(
                            value: pos,
                            min: 0,
                            max: safeMax,
                            onChangeStart: (_) {
                              _controller?.pause();
                              setState(() => _isDraggingSlider = true);
                            },
                            onChanged: (v) => _controller?.seekTo(
                                Duration(milliseconds: v.toInt())),
                            onChangeEnd: (_) {
                              _controller?.play();
                              setState(() => _isDraggingSlider = false);
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
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
// Post Image
// ─────────────────────────────────────────────────────────────────────────────

class _PostImageGallery extends StatefulWidget {
  final List<String> imageUrls;
  final bool isDark;
  final VoidCallback? onImageTap;
  const _PostImageGallery({
    required this.imageUrls,
    required this.isDark,
    this.onImageTap,
  });

  @override
  State<_PostImageGallery> createState() => _PostImageGalleryState();
}

class _PostImageGalleryState extends State<_PostImageGallery> {
  static const gold = Color(0xFFD4A017);
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _resolveAspect();
  }

  void _resolveAspect() {
    if (widget.imageUrls.isEmpty) return;
    final imageProvider = NetworkImage(widget.imageUrls.first);
    final stream = imageProvider.resolve(ImageConfiguration.empty);
    stream.addListener(
      ImageStreamListener((info, _) {
        if (!mounted) return;
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        setState(() => _aspectRatio = w / h);
      }, onError: (_, __) {}),
    );
  }

  void _openFullScreen(BuildContext context, int initialIndex) {
    if (widget.onImageTap != null) {
      widget.onImageTap!();
      return;
    }
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: _FullScreenGallery(
            imageUrls: widget.imageUrls,
            initialIndex: initialIndex,
          ),
        ),
      ),
    );
  }

  Widget _img(String url, {BoxFit fit = BoxFit.cover}) {
    final isDark = widget.isDark;
    return Image.network(
      url,
      fit: fit,
      headers: const {'Accept': 'image/*'},
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: isDark ? const Color(0xFF222222) : const Color(0xFFEFE7D8),
          child: const Center(
            child: CircularProgressIndicator(color: gold, strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (_, __, ___) => Container(
        color: isDark ? const Color(0xFF222222) : const Color(0xFFEFE7D8),
        child: const Icon(Icons.broken_image_outlined,
            color: Colors.black38, size: 42),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls;
    final isDark = widget.isDark;
    final double ratio = (_aspectRatio != null && _aspectRatio! < 0.9)
        ? 1.0
        : (_aspectRatio ?? 16 / 9);

    if (urls.length == 1) {
      return GestureDetector(
        onTap: () => _openFullScreen(context, 0),
        child: AspectRatio(
          aspectRatio: ratio,
          child: _img(urls[0]),
        ),
      );
    }

    if (urls.length == 2) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Row(
          children: [
            for (int i = 0; i < 2; i++) ...[
              if (i == 1) const SizedBox(width: 2),
              Expanded(
                child: GestureDetector(
                  onTap: () => _openFullScreen(context, i),
                  child: _img(urls[i]),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (urls.length == 3) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _openFullScreen(context, 0),
                child: _img(urls[0]),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openFullScreen(context, 1),
                      child: _img(urls[1]),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openFullScreen(context, 2),
                      child: _img(urls[2]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 4 images — 2x2 grid
    return AspectRatio(
      aspectRatio: 1,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openFullScreen(context, 0),
                    child: _img(urls[0]),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openFullScreen(context, 1),
                    child: _img(urls[1]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openFullScreen(context, 2),
                    child: _img(urls[2]),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openFullScreen(context, 3),
                    child: _img(urls[3]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full Screen Image Gallery (swipeable)
// ─────────────────────────────────────────────────────────────────────────────

class _FullScreenGallery extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  const _FullScreenGallery({required this.imageUrls, required this.initialIndex});

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late PageController _pageController;
  late int _currentIndex;
  double _dragOffset = 0;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _controller.reverse().then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final opacity = (1.0 - (_dragOffset.abs() / 300)).clamp(0.0, 1.0);
    final urls = widget.imageUrls;

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) =>
          Opacity(opacity: _controller.value, child: child),
      child: GestureDetector(
        onTap: _dismiss,
        child: Scaffold(
          backgroundColor: Colors.black.withOpacity(opacity),
          body: Stack(
            children: [
              GestureDetector(
                onVerticalDragUpdate: (d) {
                  setState(() => _dragOffset += d.delta.dy);
                },
                onVerticalDragEnd: (d) {
                  if (_dragOffset.abs() > 100 ||
                      d.primaryVelocity!.abs() > 600) {
                    _dismiss();
                  } else {
                    setState(() => _dragOffset = 0);
                  }
                },
                onTap: () {},
                child: Transform.translate(
                  offset: Offset(0, _dragOffset),
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: urls.length,
                    onPageChanged: (i) => setState(() => _currentIndex = i),
                    itemBuilder: (context, index) => Center(
                      child: InteractiveViewer(
                        child: Image.network(
                          urls[index],
                          fit: BoxFit.contain,
                          headers: const {'Accept': 'image/*'},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (urls.length > 1)
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(urls.length, (i) {
                          final active = i == _currentIndex;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: active ? 10 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: active
                                  ? const Color(0xFFD4A017)
                                  : Colors.white.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// State message
// ─────────────────────────────────────────────────────────────────────────────

class _StateMessage extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  final String message;
  final String buttonText;
  final Future<void> Function() onPressed;

  const _StateMessage({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.message,
    required this.buttonText,
    required this.onPressed,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white60 : Colors.black54;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: gold, size: 48),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: textSub, fontSize: 13, height: 1.6)),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: gold,
                side: const BorderSide(color: gold),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}