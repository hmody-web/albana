import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource, XFile;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  String get timeAgo {
    if (createdAt.isEmpty) return '';
    try {
      final dt = DateTime.parse(createdAt);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'الآن';
      if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
      if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
      if (diff.inDays < 7) return 'منذ ${diff.inDays} يوم';
      return createdAt.split(' ').first;
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
  static const String _commentsApi =
      'https://majidalbana.com/admin/comments/load_comments.php';
  static const String _addCommentApi =
      'https://majidalbana.com/admin/comments/add_comment.php';

  bool _expanded = false;
  bool _liked = false;
  final _commentCtrl = TextEditingController();
  bool _sendingComment = false;
  List<_Comment> _comments = [];
  bool _loadingComments = false;
  bool _commentsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadCommentCount();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCommentCount() async {
    try {
      final res = await http.get(
        Uri.parse('$_commentsApi?post_id=${widget.post.id}&count_only=1'),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final count = int.tryParse('${data['count'] ?? 0}') ?? 0;
        if (count > 0 && _comments.isEmpty) {
          setState(() => _comments = List.generate(count, (i) => _Comment(
            id: i, postId: widget.post.id,
            userName: '', userAvatar: '', text: '', createdAt: '',
          )));
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
                          color: _liked ? gold : gold.withOpacity(0.3),
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

                  // Comments count badge — taps open detail page
                  if (commentCount > 0)
                    GestureDetector(
                      onTap: _openPostDetail,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: gold.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: gold.withOpacity(0.35)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded,
                                size: 15, color: gold),
                            const SizedBox(width: 6),
                            Text(
                              '$commentCount ${commentCount == 1 ? 'تعليق' : 'تعليقات'}',
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
// Comment Input Box (logged in)
// ─────────────────────────────────────────────────────────────────────────────

class _CommentInputBox extends StatelessWidget {
  final bool isDark;
  final User user;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _CommentInputBox({
    required this.isDark,
    required this.user,
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final fieldBg = isDark ? const Color(0xFF242424) : const Color(0xFFF5F1EA);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final hintColor = isDark ? Colors.white38 : Colors.black38;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // User Avatar
        CircleAvatar(
          radius: 18,
          backgroundImage: user.photoURL != null
              ? NetworkImage(user.photoURL!)
              : null,
          backgroundColor: gold.withOpacity(0.2),
          child: user.photoURL == null
              ? Icon(Icons.person_rounded, color: gold, size: 18)
              : null,
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
                Expanded(
                  child: TextField(
                    controller: controller,
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
                // Send button
                Padding(
                  padding: const EdgeInsets.only(left: 6, right: 4, bottom: 5),
                  child: GestureDetector(
                    onTap: sending ? null : onSend,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: sending
                            ? gold.withOpacity(0.4)
                            : gold,
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
                              Text(
                                'تسجيل الدخول بـ Google',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
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

  const _PostDetailPage({required this.post, required this.isDark});

  @override
  State<_PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<_PostDetailPage> {
  static const gold = Color(0xFFD4A017);
  static const String _commentsApi =
      'https://majidalbana.com/admin/comments/load_comments.php';
  static const String _addCommentApi =
      'https://majidalbana.com/admin/comments/add_comment.php';

  List<_Comment> _comments = [];
  bool _loadingComments = true;
  bool _sendingComment = false;
  final _commentCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _loadingComments = true);
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
          });
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

    return Scaffold(
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
                // Post Image
                if (p.image.trim().isNotEmpty)
                  _PostImage(imageUrl: p.imageUrl, isDark: isDark),

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
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundImage:
                                const AssetImage('assets/images/majid.png'),
                            backgroundColor: gold.withOpacity(0.15),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('د.ماجد البنا',
                                  style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                              Row(
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
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 16,
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
                    .map((c) => _CommentBubble(
                          comment: c,
                          isDark: isDark,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Comment Bubble
// ─────────────────────────────────────────────────────────────────────────────

class _CommentBubble extends StatelessWidget {
  final _Comment comment;
  final bool isDark;

  const _CommentBubble({required this.comment, required this.isDark});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final bubbleBg = isDark ? const Color(0xFF222222) : const Color(0xFFFAF6EF);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white54 : Colors.black45;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User Avatar
          CircleAvatar(
            radius: 19,
            backgroundImage: comment.userAvatar.isNotEmpty
                ? NetworkImage(comment.userAvatar)
                : null,
            backgroundColor: gold.withOpacity(0.2),
            child: comment.userAvatar.isEmpty
                ? Text(
                    comment.userName.isNotEmpty
                        ? comment.userName[0].toUpperCase()
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  decoration: BoxDecoration(
                    color: bubbleBg,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(4),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: Border.all(
                        color: gold.withOpacity(0.1), width: 0.8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment.userName,
                        style: TextStyle(
                          color: gold,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        comment.text,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 13.5,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    comment.timeAgo,
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