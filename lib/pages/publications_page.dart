import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource, XFile;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/shared_widgets.dart';

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

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.isDark ? const Color(0xFF101010) : const Color(0xFFF7F4EE);

    return CustomScrollView(
      keyboardDismissBehavior:
    ScrollViewKeyboardDismissBehavior.onDrag,
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
  File? _pickedImage;
  bool _publishing = false;
  bool _expanded = false;

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _pickedImage = File(picked.path));
  }

  Future<void> _publish() async {
    if (_pickedImage == null) {
      _showSnack('الصورة مطلوبة للنشر');
      return;
    }
    setState(() => _publishing = true);
    try {
      final request =
          http.MultipartRequest('POST', Uri.parse(widget.addPostApi));
      request.fields['content'] = _contentCtrl.text.trim();
      request.files.add(
        await http.MultipartFile.fromPath('image', _pickedImage!.path),
      );
      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
      if (streamed.statusCode == 200 || streamed.statusCode == 302) {
        _contentCtrl.clear();
        setState(() {
          _pickedImage = null;
          _expanded = false;
          _publishing = false;
        });
        _showSnack('تم النشر بنجاح ✓', success: true);
        widget.onPublished();
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
                    // Image picker
                    GestureDetector(
                      onTap: _pickedImage == null ? _pickImage : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: _pickedImage != null ? 200 : 110,
                        decoration: BoxDecoration(
                          color: fieldBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _pickedImage != null
                                ? gold.withOpacity(0.5)
                                : borderColor,
                            width: 1.5,
                          ),
                        ),
                        child: _pickedImage != null
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: Image.file(_pickedImage!,
                                        fit: BoxFit.cover),
                                  ),
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: GestureDetector(
                                      onTap: _pickImage,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color:
                                              Colors.black.withOpacity(0.65),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.swap_horiz_rounded,
                                                color: Colors.white,
                                                size: 14),
                                            SizedBox(width: 5),
                                            Text('تغيير الصورة',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11.5,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: GestureDetector(
                                      onTap: () => setState(
                                          () => _pickedImage = null),
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color:
                                              Colors.red.withOpacity(0.8),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                            Icons.close_rounded,
                                            color: Colors.white,
                                            size: 16),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(
                                      Icons.add_photo_alternate_rounded,
                                      color: gold.withOpacity(0.7),
                                      size: 32),
                                  const SizedBox(height: 7),
                                  Text('اضغط لإرفاق صورة',
                                      style: TextStyle(
                                          color: hintColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                      ),
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
// Model
// ─────────────────────────────────────────────────────────────────────────────

class _PublicationPost {
  final int id;
  final String image;
  final String content;
  final String createdAt;

  const _PublicationPost({
    required this.id,
    required this.image,
    required this.content,
    required this.createdAt,
  });

  factory _PublicationPost.fromJson(Map<String, dynamic> json) {
    return _PublicationPost(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      image: '${json['image'] ?? ''}',
      content: _cleanText('${json['content'] ?? ''}'),
      createdAt: '${json['created_at'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'image': image,
        'content': content,
        'created_at': createdAt,
      };

  _PublicationPost copyWith({String? content, String? image}) {
    return _PublicationPost(
      id: id,
      image: image ?? this.image,
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

  String get formattedDate {
    if (createdAt.isEmpty) return 'منشور حديث';
    final parts = createdAt.split(RegExp(r'[ T]'));
    return parts.first;
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

  const _PostCard({
    required this.post,
    required this.isDark,
    this.showOfflineBanner = false,
    required this.isSupervisor,
    required this.onEdited,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  static const gold = Color(0xFFD4A017);
  bool _expanded = false;
  bool _liked = false;

  void _openEditSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditPostSheet(
        post: widget.post,
        isDark: widget.isDark,
        onSaved: widget.onEdited,
      ),
    );
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

    return Container(
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
            if (p.image.trim().isNotEmpty)
              _PostImage(imageUrl: p.imageUrl, isDark: isDark),

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
                    Text(
                      'لا يوجد اتصال بالإنترنت — المحتوى غير متاح',
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
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
                  // Edit button (supervisor only)
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
                            Icon(Icons.edit_rounded,
                                size: 13, color: gold),
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
              child: Text(
                p.content.isEmpty ? 'منشور بدون وصف' : p.content,
                maxLines: _expanded ? null : 4,
                overflow:
                    _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 14.5,
                  height: 1.75,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            Divider(
                height: 20,
                thickness: 0.5,
                indent: 18,
                endIndent: 18,
                color: dividerColor),

            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _liked = !_liked),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _liked
                            ? gold.withOpacity(0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color:
                              _liked ? gold : gold.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _liked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 16,
                            color: gold,
                          ),
                          const SizedBox(width: 6),
                          Text('إعجاب',
                              style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _expanded = !_expanded),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: gold.withOpacity(0.4)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _expanded ? 'عرض أقل' : 'اقرأ المزيد',
                            style: TextStyle(
                                color: textPrimary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.arrow_back_ios_rounded,
                            size: _expanded ? 17 : 12,
                            color: textPrimary,
                          ),
                        ],
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
              // Handle
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
              // Title
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
                    // Image area
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
                                          color:
                                              gold.withOpacity(0.4),
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
                                              fontWeight:
                                                  FontWeight.w700)),
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
                    // Save button
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: gold,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              gold.withOpacity(0.5),
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
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
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
// Post Image
// ─────────────────────────────────────────────────────────────────────────────

class _PostImage extends StatefulWidget {
  final String imageUrl;
  final bool isDark;
  const _PostImage({required this.imageUrl, required this.isDark});

  @override
  State<_PostImage> createState() => _PostImageState();
}

class _PostImageState extends State<_PostImage> {
  static const gold = Color(0xFFD4A017);
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _resolveAspect();
  }

  void _resolveAspect() {
    final imageProvider = NetworkImage(widget.imageUrl);
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

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final double ratio = (_aspectRatio != null && _aspectRatio! < 0.9)
        ? 1.0
        : (_aspectRatio ?? 16 / 9);

    return GestureDetector(
      onTap: () => _openFullScreen(context),
      child: AspectRatio(
        aspectRatio: ratio,
        child: Image.network(
          widget.imageUrl,
          fit: BoxFit.cover,
          headers: const {'Accept': 'image/*'},
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              color: isDark
                  ? const Color(0xFF222222)
                  : const Color(0xFFEFE7D8),
              child: const Center(
                child: CircularProgressIndicator(
                    color: gold, strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (_, __, ___) => Container(
            color: isDark
                ? const Color(0xFF222222)
                : const Color(0xFFEFE7D8),
            child: Icon(Icons.broken_image_outlined,
                color: Colors.black38, size: 42),
          ),
        ),
      ),
    );
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: _FullScreenImage(imageUrl: widget.imageUrl),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full Screen Image Viewer
// ─────────────────────────────────────────────────────────────────────────────

class _FullScreenImage extends StatefulWidget {
  final String imageUrl;
  const _FullScreenImage({required this.imageUrl});

  @override
  State<_FullScreenImage> createState() => _FullScreenImageState();
}

class _FullScreenImageState extends State<_FullScreenImage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _dragOffset = 0;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
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

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) =>
          Opacity(opacity: _controller.value, child: child),
      child: GestureDetector(
        onTap: _dismiss,
        child: Scaffold(
          backgroundColor: Colors.black.withOpacity(opacity),
          body: GestureDetector(
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
              child: Center(
                child: InteractiveViewer(
                  child: Image.network(
                    widget.imageUrl,
                    fit: BoxFit.contain,
                    headers: const {'Accept': 'image/*'},
                  ),
                ),
              ),
            ),
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