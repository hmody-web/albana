import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  static const String _cacheKey = 'cached_posts';

  List<_PublicationPost> _posts = [];
  bool _initialLoading = true;
  bool _isOffline = false;
  /// IDs already saved in cache — used to detect truly new posts
  Set<int> _cachedIds = {};
  Timer? _pollingTimer;

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

  // Load from cache first, then fetch silently in background
  Future<void> _initPosts() async {
    final cached = await _loadFromCache();
    if (cached.isNotEmpty) {
      _cachedIds = cached.map((p) => p.id).toSet();
      setState(() {
        _posts = cached;
        _initialLoading = false;
      });
    }
    // Fetch fresh data in background
    await _fetchAndUpdate(showLoadingIfEmpty: cached.isEmpty);
    // Start polling every 30 seconds for real-time updates
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

      // Only add posts whose IDs we haven't seen before
      final newPosts = freshPosts
          .where((p) => !_cachedIds.contains(p.id))
          .toList();

      if (newPosts.isNotEmpty || _initialLoading) {
        // Prepend new posts at the top, keep existing ones unchanged
        final merged = [...newPosts, ..._posts];
        _cachedIds = merged.map((p) => p.id).toSet();
        setState(() {
          _posts = merged;
          _initialLoading = false;
          _isOffline = false;
        });
        await _saveToCache(merged);
      } else {
        // No new posts — just clear offline flag if it was set
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

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.isDark ? const Color(0xFF101010) : const Color(0xFFF7F4EE);

    return CustomScrollView(
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

    // No cache at all + offline → full-page error
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

    if (_posts.isEmpty) {
      return _StateMessage(
        isDark: widget.isDark,
        icon: Icons.article_outlined,
        title: 'لا توجد منشورات',
        message: 'عند إضافة منشور من لوحة التحكم سيظهر هنا مباشرة.',
        buttonText: 'تحديث',
        onPressed: _refreshPosts,
      );
    }

    return RefreshIndicator(
      color: gold,
      onRefresh: _refreshPosts,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          final post = _posts[index];
          final isCached = _cachedIds.contains(post.id);
          return _PostCard(
            post: post,
            isDark: widget.isDark,
            // Mark uncached posts as offline so card can show the banner
            showOfflineBanner: _isOffline && !isCached,
          );
        },
      ),
    );
  }
}

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

  /// Returns only the date part (YYYY-MM-DD or formatted) — strips time
  String get formattedDate {
    if (createdAt.isEmpty) return 'منشور حديث';
    // Split on space or T to remove time portion
    final parts = createdAt.split(RegExp(r'[ T]'));
    return parts.first; // e.g. "2024-05-12"
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Post Card
// ─────────────────────────────────────────────────────────────────────────────

class _PostCard extends StatefulWidget {
  final _PublicationPost post;
  final bool isDark;
  final bool showOfflineBanner;

  const _PostCard({
    required this.post,
    required this.isDark,
    this.showOfflineBanner = false,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  static const gold = Color(0xFFD4A017);
  bool _expanded = false;
  bool _liked = false;

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
            // ── Image (aspect-ratio aware) ────────────────────────────────
            if (p.image.trim().isNotEmpty)
              _PostImage(imageUrl: p.imageUrl, isDark: isDark),

            // ── Offline banner (shown only for uncached posts) ────────────
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

            // ── Author Row ────────────────────────────────────────────────
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
                  Column(
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
                ],
              ),
            ),

            // ── Content ───────────────────────────────────────────────────
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

            // ── Bottom Row: Like + Read More ──────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                          color: _liked
                              ? gold
                              : gold.withOpacity(0.3),
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
                          Text(
                            'إعجاب',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Read more button
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: gold.withOpacity(0.4)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _expanded ? 'عرض أقل' : 'اقرأ المزيد',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
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
// Post Image — aspect-ratio aware + tap to open full-screen
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
    // If portrait (ratio < 0.9) → force square display; otherwise natural ratio
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
// Full-screen image viewer — close on drag or tap outside
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
      builder: (_, child) => Opacity(
        opacity: _controller.value,
        child: child,
      ),
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
            onTap: () {}, // prevent scaffold tap propagation
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
// State message (empty / error)
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
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: textSub, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: gold,
                side: const BorderSide(color: gold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}