import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
import 'package:video_thumbnail/video_thumbnail.dart';

bool _isSupervisorEmail(String? email) {
  final cleanEmail = email?.trim().toLowerCase();
  return cleanEmail == 'hmode.qq@gmail.com' || cleanEmail == 'hmode.qu@gmail.com';
}

bool _isCurrentUserSupervisor() {
  return _isSupervisorEmail(FirebaseAuth.instance.currentUser?.email);
}

class _FullWidthRectSliderTrackShape extends RectangularSliderTrackShape {
  const _FullWidthRectSliderTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 2.0;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;

    return Rect.fromLTWH(
      offset.dx,
      trackTop,
      parentBox.size.width,
      trackHeight,
    );
  }
}
class _GlobalVideoMute {
  static final ValueNotifier<bool> muted = ValueNotifier<bool>(false);

  static bool get isMuted => muted.value;

  static void toggle() {
    muted.value = !muted.value;
  }

  static double get volume => muted.value ? 0.0 : 1.0;

  static void applyTo(VideoPlayerController? controller) {
    if (controller == null) return;

    try {
      controller.setVolume(volume).catchError((e) {
        debugPrint('Safe video volume error: $e');
      });
    } catch (e) {
      debugPrint('Safe video volume sync error: $e');
    }
  }
}
class _VisibleVideoCoordinator {
  static final ValueNotifier<String?> activeVideoId =
      ValueNotifier<String?>(null);

  static final Map<String, double> _visibleFractions = {};

  static const double _minVisibleToPlay = 0.35;

  static void update(String id, double visibleFraction) {
    _visibleFractions[id] = visibleFraction;
    _pickMostVisible();
  }

  static void remove(String id) {
    _visibleFractions.remove(id);
    if (activeVideoId.value == id) {
      _pickMostVisible();
    }
  }

  static void clearActive() {
    if (activeVideoId.value != null) {
      activeVideoId.value = null;
    }
  }

  static void _pickMostVisible() {
    String? bestId;
    double bestFraction = _minVisibleToPlay - 0.001;

    _visibleFractions.forEach((id, fraction) {
      if (fraction > bestFraction) {
        bestFraction = fraction;
        bestId = id;
      }
    });

    if (activeVideoId.value != bestId) {
      activeVideoId.value = bestId;
    }
  }
}

class _PostRealtimeSnapshot {
  final int? likesCount;
  final bool? liked;
  final List<_Comment>? comments;

  const _PostRealtimeSnapshot({
    this.likesCount,
    this.liked,
    this.comments,
  });

  _PostRealtimeSnapshot copyWith({
    int? likesCount,
    bool? liked,
    List<_Comment>? comments,
  }) {
    return _PostRealtimeSnapshot(
      likesCount: likesCount ?? this.likesCount,
      liked: liked ?? this.liked,
      comments: comments ?? this.comments,
    );
  }
}

class _PostRealtimeBus {
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
  static final Map<int, _PostRealtimeSnapshot> _snapshots = {};

  static _PostRealtimeSnapshot? snapshot(int postId) => _snapshots[postId];

  static String commentsFingerprint(List<_Comment> list) {
    return list
        .map((c) => '${c.id}|${c.text}|${c.createdAt}|${c.userName}')
        .join('::');
  }

  static bool commentsChanged(List<_Comment> oldList, List<_Comment> newList) {
    return commentsFingerprint(oldList) != commentsFingerprint(newList);
  }

  static void publishLikes(
    int postId, {
    required int likesCount,
    required bool liked,
  }) {
    final old = _snapshots[postId];
    if (old?.likesCount == likesCount && old?.liked == liked) return;

    _snapshots[postId] = (old ?? const _PostRealtimeSnapshot()).copyWith(
      likesCount: likesCount,
      liked: liked,
    );
    tick.value++;
  }

  static void publishComments(int postId, List<_Comment> comments) {
    final safeComments = _Comment.newestFirst(comments);
    final old = _snapshots[postId];
    if (old?.comments != null &&
        !commentsChanged(old!.comments!, safeComments)) {
      return;
    }

    _snapshots[postId] = (old ?? const _PostRealtimeSnapshot()).copyWith(
      comments: safeComments,
    );
    tick.value++;
  }
}

class PublicationsPageScrollBus {
  static final ValueNotifier<int> goTopSignal = ValueNotifier<int>(0);

  static void goTop() {
    goTopSignal.value++;
  }
}

class PublicationsPageDeepLinkBus {
  static final ValueNotifier<int?> requestedPostId = ValueNotifier<int?>(null);

  static void openPost(int postId) {
    requestedPostId.value = null;
    requestedPostId.value = postId;
  }
}


class PublicationDirectPage extends StatefulWidget {
  final int postId;
  final bool isDark;

  const PublicationDirectPage({
    super.key,
    required this.postId,
    required this.isDark,
  });

  @override
  State<PublicationDirectPage> createState() => _PublicationDirectPageState();
}

class _PublicationDirectPageState extends State<PublicationDirectPage> {
  static const String _singlePostApi =
      'https://majidalbana.com/admin/posts/get_post.php';

  late final Future<_PublicationPost?> _futurePost;

  @override
  void initState() {
    super.initState();
    _futurePost = _fetchPost();
  }

  Future<_PublicationPost?> _fetchPost() async {
    try {
      final uri = Uri.parse(_singlePostApi).replace(
        queryParameters: {'id': '${widget.postId}'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['success'] == true && decoded['post'] is Map) {
        return _PublicationPost.fromJson(
          Map<String, dynamic>.from(decoded['post'] as Map),
        );
      }
      if (decoded is Map && decoded['id'] != null) {
        return _PublicationPost.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pageBg = widget.isDark ? const Color(0xFF050505) : const Color(0xFFF8F6F0);

    return FutureBuilder<_PublicationPost?>(
      future: _futurePost,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: pageBg,
            body: const Center(
              child: CircularProgressIndicator(color: Color(0xFFD4A017)),
            ),
          );
        }

        final post = snapshot.data;
        if (post == null) {
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
                  'تعذر فتح المنشور المطلوب',
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

        return _PostDetailPage(
          post: post,
          isDark: widget.isDark,
          isSupervisor: _isCurrentUserSupervisor(),
        );
      },
    );
  }
}

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
  static const String _singlePostApi =
      'https://majidalbana.com/admin/posts/get_post.php';
  static const String _cacheKey = 'cached_posts';

  List<_PublicationPost> _posts = [];
  bool _initialLoading = true;
  bool _isOffline = false;
  Set<int> _cachedIds = {};
  Timer? _pollingTimer;
  bool _fetchingPosts = false;
  final Set<int> _appearingPostIds = <int>{};
  final Set<int> _removingPostIds = <int>{};


  final TextEditingController _publicationsSearchCtrl = TextEditingController();
  final FocusNode _publicationsSearchFocus = FocusNode();
  final ScrollController _postsScrollController = ScrollController();

  bool _publicationsSearchOpen = false;
  bool _publicationHeaderAvatarOnTop = true;

  bool _isSupervisor() {
    return _isCurrentUserSupervisor();
  }

  @override
  void initState() {
    super.initState();
    _publicationsSearchCtrl.addListener(_onPublicationsSearchTyping);
    PublicationsPageScrollBus.goTopSignal.addListener(_scrollPostsToTop);
    PublicationsPageDeepLinkBus.requestedPostId.addListener(_onDeepLinkPostRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onDeepLinkPostRequested();
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _initPosts();
      });
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    PublicationsPageScrollBus.goTopSignal.removeListener(_scrollPostsToTop);
    PublicationsPageDeepLinkBus.requestedPostId.removeListener(_onDeepLinkPostRequested);
    _publicationsSearchCtrl.removeListener(_onPublicationsSearchTyping);
    _publicationsSearchCtrl.dispose();
    _publicationsSearchFocus.dispose();
    _postsScrollController.dispose();
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
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
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

  bool _isSamePostData(_PublicationPost a, _PublicationPost b) {
    return a.id == b.id &&
        a.image == b.image &&
        a.content == b.content &&
        a.createdAt == b.createdAt &&
        a.images.join('||') == b.images.join('||');
  }

  Future<void> _clearAppearingMarkLater(int id) async {
    await Future.delayed(const Duration(milliseconds: 950));
    if (!mounted) return;
    if (_appearingPostIds.remove(id)) {
      setState(() {});
    }
  }

  Future<void> _removePostsAfterAnimation(
    List<int> ids,
    List<_PublicationPost> cachePosts,
  ) async {
    await Future.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;

    setState(() {
      _posts.removeWhere((p) => ids.contains(p.id));
      for (final id in ids) {
        _removingPostIds.remove(id);
        _appearingPostIds.remove(id);
        _cachedIds.remove(id);
      }
    });

    await _saveToCache(cachePosts);
  }

  Future<void> _fetchAndUpdate({bool showLoadingIfEmpty = false}) async {
    if (_fetchingPosts) return;
    _fetchingPosts = true;

    if (showLoadingIfEmpty && _posts.isEmpty) {
      setState(() => _initialLoading = true);
    }

    try {
      final response = await http
          .get(Uri.parse(_postsApi))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        if (mounted) {
          if (_posts.isEmpty) setState(() => _initialLoading = false);
          setState(() => _isOffline = true);
        }
        return;
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) {
        if (mounted && _posts.isEmpty) {
          setState(() => _initialLoading = false);
        }
        return;
      }

      final freshPosts = decoded
          .whereType<Map>()
          .map((item) =>
              _PublicationPost.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      final freshIds = freshPosts.map((p) => p.id).toSet();
      final currentIds = _posts.map((p) => p.id).toSet();
      final currentById = {for (final p in _posts) p.id: p};

      final addedIds = _posts.isEmpty
          ? <int>{}
          : freshIds
              .where((id) => !currentIds.contains(id) && !_removingPostIds.contains(id))
              .toSet();

      final removedIds = currentIds
          .where((id) => !freshIds.contains(id) && !_removingPostIds.contains(id))
          .toList();

      var nextPosts = List<_PublicationPost>.from(freshPosts);

      for (final removedId in removedIds) {
        final oldPost = currentById[removedId];
        if (oldPost == null) continue;
        final oldIndex = _posts.indexWhere((p) => p.id == removedId);
        final insertIndex = oldIndex.clamp(0, nextPosts.length) as int;
        nextPosts.insert(insertIndex, oldPost);
      }

      bool changed = _initialLoading || _isOffline || addedIds.isNotEmpty || removedIds.isNotEmpty;

      if (!changed && _posts.length == nextPosts.length) {
        for (var i = 0; i < nextPosts.length; i++) {
          if (!_isSamePostData(_posts[i], nextPosts[i])) {
            changed = true;
            break;
          }
        }
      } else if (_posts.length != nextPosts.length) {
        changed = true;
      }

      if (changed && mounted) {
        setState(() {
          _posts = nextPosts;
          _cachedIds = freshIds;
          _appearingPostIds.addAll(addedIds);
          _removingPostIds.addAll(removedIds);
          _initialLoading = false;
          _isOffline = false;
        });

        for (final id in addedIds) {
          unawaited(_clearAppearingMarkLater(id));
        }

        if (removedIds.isNotEmpty) {
          unawaited(_removePostsAfterAnimation(removedIds, freshPosts));
        } else {
          await _saveToCache(freshPosts);
        }
      } else {
        if (mounted && (_isOffline || _initialLoading)) {
          setState(() {
            _isOffline = false;
            _initialLoading = false;
          });
        }
        await _saveToCache(freshPosts);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isOffline = true;
          if (_initialLoading) _initialLoading = false;
        });
      }
    } finally {
      _fetchingPosts = false;
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
    if (_removingPostIds.contains(id)) return;

    setState(() {
      _removingPostIds.add(id);
    });

    final cachePosts = _posts.where((p) => p.id != id).toList();
    unawaited(_removePostsAfterAnimation([id], cachePosts));
  }

  void _onDeepLinkPostRequested() {
    final postId = PublicationsPageDeepLinkBus.requestedPostId.value;
    if (postId == null || postId <= 0) return;

    PublicationsPageDeepLinkBus.requestedPostId.value = null;
    _openPostFromDeepLink(postId);
  }

  Future<_PublicationPost?> _fetchSinglePost(int postId) async {
    try {
      final uri = Uri.parse(_singlePostApi).replace(
        queryParameters: {'id': '$postId'},
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is Map && decoded['success'] == true && decoded['post'] is Map) {
        return _PublicationPost.fromJson(
          Map<String, dynamic>.from(decoded['post'] as Map),
        );
      }

      if (decoded is Map && decoded['id'] != null) {
        return _PublicationPost.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}

    return null;
  }

  Future<void> _openPostFromDeepLink(int postId) async {
    if (!mounted) return;

    _publicationsSearchFocus.unfocus();

    _PublicationPost? post;
    for (final item in _posts) {
      if (item.id == postId) {
        post = item;
        break;
      }
    }

    post ??= await _fetchSinglePost(postId);

    if (!mounted) return;

    if (post == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر فتح المنشور من الرابط',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
      return;
    }

    final postToOpen = post;

    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, animation, __) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: _PostDetailPage(
              post: postToOpen,
              isDark: widget.isDark,
              isSupervisor: _isSupervisor(),
            ),
          );
        },
      ),
    );
  }

  void _scrollPostsToTop() {
    if (!_postsScrollController.hasClients) return;

    _postsScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPublicationsSearchTyping() {
    if (mounted && _publicationsSearchOpen) {
      setState(() {});
    }
  }

  void _togglePublicationsSearch() {
    setState(() {
      _publicationsSearchOpen = !_publicationsSearchOpen;
    });

    if (_publicationsSearchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _publicationsSearchFocus.requestFocus();
        }
      });
    } else {
      _publicationsSearchFocus.unfocus();
      _publicationsSearchCtrl.clear();
    }
  }

  void _toggleHeaderAvatarLogo() {
    setState(() {
      _publicationHeaderAvatarOnTop = !_publicationHeaderAvatarOnTop;
    });
  }

 Future<void> _openPublicationFromSearch(_PublicationPost post) async {
  // نخفي الكيبورد فقط، لكن لا نغلق البحث ولا نمسح النص
  _publicationsSearchFocus.unfocus();

  await Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, animation, __) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: _PostDetailPage(
            post: post,
            isDark: widget.isDark,
            isSupervisor: _isSupervisor(),
          ),
        );
      },
    ),
  );

  // بعد الرجوع نخلي البحث مفتوح مثل ما كان
  if (!mounted) return;

  if (!_publicationsSearchOpen) {
    setState(() {
      _publicationsSearchOpen = true;
    });
  } else {
    setState(() {});
  }
}

  String _normalizePublicationsSearch(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll(RegExp(r'[إأآا]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll(RegExp(r'[^\u0600-\u06FFa-z0-9]+'), ' ')
        .trim();
  }

  List<_PublicationPost> _publicationsSearchResults() {
    final query = _normalizePublicationsSearch(_publicationsSearchCtrl.text);
    final sorted = List<_PublicationPost>.from(_posts);

    if (query.isEmpty) {
      return sorted.take(6).toList();
    }

    final tokens = query.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final exact = sorted.where((post) {
      final haystack = _normalizePublicationsSearch(
        '${post.content} ${post.formattedDate} ${post.createdAt}',
      );
      return tokens.every(haystack.contains);
    }).toList();

    if (exact.isNotEmpty) {
      return exact.take(8).toList();
    }

    final relaxed = sorted.where((post) {
      final haystack = _normalizePublicationsSearch(
        '${post.content} ${post.formattedDate} ${post.createdAt}',
      );
      return tokens.any(haystack.contains);
    }).toList();

    return relaxed.take(8).toList();
  }

  Widget _buildPublicationsHeaderSliver(Color bgColor) {
    return _PublicationsOldTopAppBarV5(
      isDark: widget.isDark,
      avatarOnTop: _publicationHeaderAvatarOnTop,
      searchOpen: _publicationsSearchOpen,
      onAvatarLogoTap: _toggleHeaderAvatarLogo,
      onSearchTap: _togglePublicationsSearch,
    );
  }

  Widget _buildPublicationsSearchSliver(Color bgColor) {
    return SliverToBoxAdapter(
      child: Container(
        color: bgColor,
        padding: EdgeInsets.fromLTRB(
          16,
          _publicationsSearchOpen ? 10 : 0,
          16,
          _publicationsSearchOpen ? 10 : 0,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _publicationsSearchOpen
              ? _PublicationsSearchPanelV4(
                  key: const ValueKey('publications_search_panel_v5_old_bar'),
                  isDark: widget.isDark,
                  controller: _publicationsSearchCtrl,
                  focusNode: _publicationsSearchFocus,
                  results: _publicationsSearchResults(),
                  onClose: _togglePublicationsSearch,
                  onOpenPost: _openPublicationFromSearch,
                )
              : const SizedBox.shrink(
                  key: ValueKey('publications_search_panel_closed_v5_old_bar'),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.isDark ? const Color(0xFF101010) : const Color(0xFFF7F4EE);

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const BouncingScrollPhysics(),
      slivers: [
        _buildPublicationsHeaderSliver(bgColor),
        _buildPublicationsSearchSliver(bgColor),
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
  controller: _postsScrollController,
  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
  // نخلي كروت الفيديو تبقى حية بعد ما تعبرها بالسكرول،
        // حتى ما يرجع الفيديو يحمل من الصفر عند الرجوع له.
        cacheExtent: 1800,
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: true,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
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
          return _AnimatedRealtimePostItem(
            key: ValueKey('post_realtime_item_${post.id}'),
            animateIn: _appearingPostIds.contains(post.id),
            animateOut: _removingPostIds.contains(post.id),
            child: _PostCard(
              key: ValueKey('post_card_${post.id}'),
              post: post,
              isDark: widget.isDark,
              showOfflineBanner: _isOffline && !isCached,
              isSupervisor: supervisor,
              onEdited: _onPostEdited,
              onDeleted: _onPostDeleted,
            ),
          );
        },
      ),
    );
  }

}

class _AnimatedRealtimePostItem extends StatefulWidget {
  final Widget child;
  final bool animateIn;
  final bool animateOut;

  const _AnimatedRealtimePostItem({
    super.key,
    required this.child,
    required this.animateIn,
    required this.animateOut,
  });

  @override
  State<_AnimatedRealtimePostItem> createState() => _AnimatedRealtimePostItemState();
}

class _AnimatedRealtimePostItemState extends State<_AnimatedRealtimePostItem> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    if (widget.animateIn) {
      _visible = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedRealtimePostItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.animateOut && widget.animateOut) {
      setState(() => _visible = false);
    }

    if (!oldWidget.animateIn && widget.animateIn && !widget.animateOut) {
      _visible = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final curve = widget.animateOut ? Curves.easeInCubic : Curves.easeOutBack;
    final duration = widget.animateOut
        ? const Duration(milliseconds: 360)
        : const Duration(milliseconds: 620);

    return AnimatedSize(
      duration: duration,
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: duration,
        curve: curve,
        opacity: _visible ? 1 : 0,
        child: AnimatedSlide(
          duration: duration,
          curve: curve,
          offset: _visible
              ? Offset.zero
              : Offset(widget.animateOut ? 0.16 : -0.08, widget.animateOut ? 0.04 : -0.10),
          child: AnimatedScale(
            duration: duration,
            curve: curve,
            scale: _visible ? 1 : (widget.animateOut ? 0.92 : 0.86),
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: _visible ? 1 : 0,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// PUBLICATIONS_OLD_STYLE_APP_BAR_V5_LOGO_2026_06_14
// شريط علوي بنفس روح PremiumAppBar القديم، مع الاحتفاظ بسويتش صورة المستخدم/اللوجو والبحث.

class _PublicationsOldTopAppBarV5 extends StatelessWidget {
  static const gold = Color(0xFFD4A017);

  final bool isDark;
  final bool avatarOnTop;
  final bool searchOpen;
  final VoidCallback onAvatarLogoTap;
  final VoidCallback onSearchTap;

  const _PublicationsOldTopAppBarV5({
    required this.isDark,
    required this.avatarOnTop,
    required this.searchOpen,
    required this.onAvatarLogoTap,
    required this.onSearchTap,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      toolbarHeight: 58,
      automaticallyImplyLeading: false,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withOpacity(0.6)
                  : Colors.white.withOpacity(0.75),
              border: Border(
                bottom: BorderSide(
                  color: gold.withOpacity(0.18),
                  width: 0.8,
                ),
              ),
            ),
          ),
        ),
      ),
      titleSpacing: 14,
      title: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            _PublicationsLogoAvatarSwitcherV4(
              avatarOnTop: avatarOnTop,
              onTap: onAvatarLogoTap,
            ),
            Container(
              width: 1,
              height: 34,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    gold.withOpacity(0.65),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            const Text(
              'المنشورات',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: gold,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            _PublicationsSearchHeaderButtonV4(
              active: searchOpen,
              isDark: isDark,
              onTap: onSearchTap,
            ),
          ],
        ),
      ),
    );
  }
}

// PUBLICATIONS_TOP_SEARCH_FIX_V4_REAL_2026_06_14
// ─────────────────────────────────────────────────────────────────────────────
// Publications custom top header + search suggestions
// ─────────────────────────────────────────────────────────────────────────────

class _PublicationsTopHeaderV4 extends StatelessWidget {
  static const gold = Color(0xFFD4A017);

  final bool isDark;
  final bool avatarOnTop;
  final bool searchOpen;
  final VoidCallback onAvatarLogoTap;
  final VoidCallback onSearchTap;

  const _PublicationsTopHeaderV4({
    required this.isDark,
    required this.avatarOnTop,
    required this.searchOpen,
    required this.onAvatarLogoTap,
    required this.onSearchTap,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = isDark ? Colors.white : const Color(0xFF1E1A14);
    final subColor = isDark ? Colors.white70 : const Color(0xFF7E735F);
    final cardColor = isDark ? const Color(0xFF171717) : Colors.white;

    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(isDark ? 0.96 : 0.98),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: gold.withOpacity(isDark ? 0.20 : 0.24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.24 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          _PublicationsSearchHeaderButtonV4(
            active: searchOpen,
            isDark: isDark,
            onTap: onSearchTap,
          ),
          const Spacer(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 178),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'المنشورات',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'آخر التحديثات والمقالات',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: subColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 38,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  gold.withOpacity(0.75),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          _PublicationsLogoAvatarSwitcherV4(
            avatarOnTop: avatarOnTop,
            onTap: onAvatarLogoTap,
          ),
        ],
      ),
    );
  }
}
class _PublicationsLogoAvatarSwitcherV4 extends StatefulWidget {
  final bool avatarOnTop;
  final VoidCallback onTap;

  const _PublicationsLogoAvatarSwitcherV4({
    required this.avatarOnTop,
    required this.onTap,
  });

  @override
  State<_PublicationsLogoAvatarSwitcherV4> createState() =>
      _PublicationsLogoAvatarSwitcherV4State();
}

class _PublicationsLogoAvatarSwitcherV4State
    extends State<_PublicationsLogoAvatarSwitcherV4> {
  static const gold = Color(0xFFD4A017);

  static const double itemSize = 40;
  static const double overlap = 18;
  static const Duration animDuration = Duration(milliseconds: 520);

  late bool _avatarDrawOnTop;

  @override
  void initState() {
    super.initState();
    _avatarDrawOnTop = widget.avatarOnTop;
  }

  @override
  void didUpdateWidget(covariant _PublicationsLogoAvatarSwitcherV4 oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.avatarOnTop != widget.avatarOnTop) {
      Future.delayed(const Duration(milliseconds: 260), () {
        if (!mounted) return;
        setState(() {
          _avatarDrawOnTop = widget.avatarOnTop;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget avatar() {
      return StreamBuilder<User?>(
        stream: FirebaseAuth.instance.userChanges(),
        initialData: FirebaseAuth.instance.currentUser,
        builder: (context, snapshot) {
          final photo = snapshot.data?.photoURL;

          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: gold.withOpacity(0.90),
                width: 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: photo != null && photo.isNotEmpty
                  ? Image.network(
                      photo,
                      key: ValueKey(photo),
                      width: itemSize,
                      height: itemSize,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.person_rounded,
                        color: gold,
                        size: 21,
                      ),
                    )
                  : const Icon(
                      Icons.person_rounded,
                      color: gold,
                      size: 21,
                    ),
            ),
          );
        },
      );
    }

    Widget logo() {
      return Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFFFFE9A9),
              ui.Color.fromARGB(255, 221, 146, 7),
            ],
          ),
          border: Border.all(
            color: Colors.white.withOpacity(0.90),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: gold.withOpacity(0.28),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipOval(
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Colors.white,
              BlendMode.srcIn,
            ),
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.school_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      );
    }

    Widget animatedItem({
      required bool isAvatar,
      required bool isFrontTarget,
    }) {
      final double rightPos;

      if (isAvatar) {
        rightPos = widget.avatarOnTop ? 0 : overlap;
      } else {
        rightPos = widget.avatarOnTop ? overlap : 0;
      }

      return AnimatedPositioned(
        duration: animDuration,
        curve: Curves.easeInOutCubicEmphasized,
        right: rightPos,
        top: 7,
        width: itemSize,
        height: itemSize,
        child: AnimatedScale(
          duration: animDuration,
          curve: Curves.easeInOutCubicEmphasized,
          scale: isFrontTarget ? 1.0 : 0.90,
          child: AnimatedRotation(
            duration: animDuration,
            curve: Curves.easeInOutCubicEmphasized,
            turns: isFrontTarget ? 0.0 : -0.025,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOut,
              opacity: isFrontTarget ? 1.0 : 0.82,
              child: isAvatar ? avatar() : logo(),
            ),
          ),
        ),
      );
    }

    final avatarWidget = animatedItem(
      isAvatar: true,
      isFrontTarget: widget.avatarOnTop,
    );

    final logoWidget = animatedItem(
      isAvatar: false,
      isFrontTarget: !widget.avatarOnTop,
    );

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: itemSize + overlap,
        height: 54,
        child: Stack(
          clipBehavior: Clip.none,
          children: _avatarDrawOnTop
              ? [
                  logoWidget,
                  avatarWidget,
                ]
              : [
                  avatarWidget,
                  logoWidget,
                ],
        ),
      ),
    );
  }
}

class _PublicationsSearchHeaderButtonV4 extends StatelessWidget {
  static const gold = Color(0xFFD4A017);

  final bool active;
  final bool isDark;
  final VoidCallback onTap;

  const _PublicationsSearchHeaderButtonV4({
    required this.active,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            color: active
                ? gold.withOpacity(isDark ? 0.22 : 0.18)
                : gold.withOpacity(isDark ? 0.12 : 0.10),
            border: Border.all(color: gold.withOpacity(active ? 0.62 : 0.25)),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Icon(
              active ? Icons.close_rounded : Icons.search_rounded,
              key: ValueKey(active),
              color: gold,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _PublicationsSearchPanelV4 extends StatelessWidget {
  static const gold = Color(0xFFD4A017);

  final bool isDark;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<_PublicationPost> results;
  final VoidCallback onClose;
  final void Function(_PublicationPost post) onOpenPost;

  const _PublicationsSearchPanelV4({
    super.key,
    required this.isDark,
    required this.controller,
    required this.focusNode,
    required this.results,
    required this.onClose,
    required this.onOpenPost,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF171717) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF221D15);
    final hintColor = isDark ? Colors.white60 : const Color(0xFF8D806B);
    final query = controller.text.trim();

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(isDark ? 0.98 : 0.99),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: gold.withOpacity(isDark ? 0.20 : 0.24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.22 : 0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            focusNode: focusNode,
            textDirection: TextDirection.rtl,
            textInputAction: TextInputAction.search,
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark ? const Color(0xFF101010) : const Color(0xFFF8F3EA),
              hintText: 'ابحث داخل المنشورات...',
              hintTextDirection: TextDirection.rtl,
              hintStyle: TextStyle(color: hintColor, fontWeight: FontWeight.w700),
              prefixIcon: const Icon(Icons.search_rounded, color: gold),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                      onPressed: controller.clear,
                      icon: Icon(Icons.close_rounded, color: hintColor),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(17),
                borderSide: BorderSide(color: gold.withOpacity(0.18)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(17),
                borderSide: BorderSide(color: gold.withOpacity(0.18)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(17),
                borderSide: BorderSide(color: gold.withOpacity(0.72), width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              query.isEmpty ? 'آخر المنشورات' : 'نتائج البحث',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: hintColor,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (results.isEmpty)
            _PublicationsSearchEmptyV4(isDark: isDark)
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 330),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: results.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final post = results[index];
                  return _PublicationsSearchResultTileV4(
                    post: post,
                    isDark: isDark,
                    onTap: () => onOpenPost(post),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _PublicationsSearchEmptyV4 extends StatelessWidget {
  final bool isDark;

  const _PublicationsSearchEmptyV4({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101010) : const Color(0xFFF8F3EA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'لا توجد نتائج مطابقة',
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          color: isDark ? Colors.white54 : const Color(0xFF8D806B),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PublicationsSearchResultTileV4 extends StatelessWidget {
  static const gold = Color(0xFFD4A017);

  final _PublicationPost post;
  final bool isDark;
  final VoidCallback onTap;

  const _PublicationsSearchResultTileV4({
    required this.post,
    required this.isDark,
    required this.onTap,
  });

  String _preview(String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= 96) return clean;
    return '${clean.substring(0, 96)}...';
  }

  @override
  Widget build(BuildContext context) {
    final tileColor = isDark ? const Color(0xFF101010) : const Color(0xFFF8F3EA);
    final textColor = isDark ? Colors.white : const Color(0xFF221D15);
    final subColor = isDark ? Colors.white60 : const Color(0xFF8A7C66);
    final imageUrl = post.imageUrls.isNotEmpty ? post.imageUrls.first : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: tileColor,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: gold.withOpacity(0.13)),
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 58,
                  height: 58,
                  color: gold.withOpacity(0.12),
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.article_rounded, color: gold),
                        )
                      : Icon(
                          post.videoUrl != null ? Icons.play_circle_fill_rounded : Icons.article_rounded,
                          color: gold,
                          size: 28,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _preview(post.content.isEmpty ? 'منشور بدون نص' : post.content),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          post.formattedDate,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: subColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(Icons.schedule_rounded, color: gold, size: 13),
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
  bool _publishDone = false;
  Timer? _publishDoneTimer;
  bool _expanded = false;
  // 'image' or 'video'
  String _mediaType = 'image';

  @override
  void dispose() {
    _publishDoneTimer?.cancel();
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
        _publishDoneTimer?.cancel();
        setState(() {
          _pickedImages = [];
          _pickedVideo = null;
          _videoDuration = null;
          _expanded = false;
          _publishing = false;
          _publishDone = true;
        });
        _publishDoneTimer = Timer(const Duration(seconds: 3), () {
          if (!mounted) return;
          setState(() => _publishDone = false);
        });
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
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        child: ElevatedButton(
                          onPressed: (_publishing || _publishDone) ? null : _publish,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _publishDone
                                ? const Color(0xFF2E7D32)
                                : gold,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _publishDone
                                ? const Color(0xFF2E7D32)
                                : gold.withOpacity(0.5),
                            disabledForegroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            switchInCurve: Curves.easeOutBack,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: _publishing
                                ? const SizedBox(
                                    key: ValueKey('publishing'),
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2.5),
                                  )
                                : _publishDone
                                    ? const Row(
                                        key: ValueKey('published'),
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.check_circle_rounded, size: 20),
                                          SizedBox(width: 8),
                                          Text('تم النشر',
                                              style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w900)),
                                        ],
                                      )
                                    : const Row(
                                        key: ValueKey('publish'),
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

// FIX_IOS_SHARE_SAFE_ORIGIN
// FIX_IOS_SHARE_PREVIEW_THUMBNAIL
String _sharePreviewFileExtension(String imageUrl, String? contentType) {
  final lowerUrl = imageUrl.toLowerCase().split('?').first;
  final lowerType = (contentType ?? '').toLowerCase();

  if (lowerType.contains('png') || lowerUrl.endsWith('.png')) {
    return 'png';
  }
  if (lowerType.contains('webp') || lowerUrl.endsWith('.webp')) {
    return 'webp';
  }
  return 'jpg';
}

String _sharePreviewMimeType(String extension) {
  switch (extension) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    default:
      return 'image/jpeg';
  }
}

Future<XFile?> _prepareIosSharePreviewThumbnail(_PublicationPost post) async {
  if (!Platform.isIOS) return null;

  final previewUrl = post.imageUrls.isNotEmpty ? post.imageUrls.first : '';
  if (previewUrl.isEmpty) return null;

  try {
    final uri = Uri.parse(previewUrl);
    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      return null;
    }

    final contentType = response.headers['content-type'];
    if (contentType != null &&
        contentType.isNotEmpty &&
        !contentType.toLowerCase().contains('image/')) {
      return null;
    }

    final extension = _sharePreviewFileExtension(previewUrl, contentType);
    final mimeType = _sharePreviewMimeType(extension);
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/ios_share_preview_${post.id}_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );

    await file.writeAsBytes(response.bodyBytes, flush: true);

    return XFile(
      file.path,
      mimeType: mimeType,
      name: 'majidalbana_post_preview.$extension',
    );
  } catch (_) {
    return null;
  }
}

Future<void> _sharePublicationPost(
  BuildContext context,
  _PublicationPost post,
) async {
  final url = 'https://majidalbana.com/post/index.php?id=${post.id}';

  Rect? shareOrigin;
  try {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final topLeft = renderObject.localToGlobal(Offset.zero);
      shareOrigin = topLeft & renderObject.size;
    }
  } catch (_) {}

  try {
    final previewThumbnail = await _prepareIosSharePreviewThumbnail(post);

    await SharePlus.instance.share(
      ShareParams(
        uri: Uri.parse(url),
        title: 'منشور د.ماجد البنا',
        previewThumbnail: previewThumbnail,
        sharePositionOrigin:
            shareOrigin ?? const Rect.fromLTWH(0, 0, 1, 1),
      ),
    );
  } catch (_) {
    try {
      await Share.share(
        url,
        sharePositionOrigin:
            shareOrigin ?? const Rect.fromLTWH(0, 0, 1, 1),
      );
      return;
    } catch (_) {}

    try {
      await Clipboard.setData(ClipboardData(text: url));
    } catch (_) {}

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر فتح نافذة المشاركة، تم نسخ الرابط',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    } catch (_) {}
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

  static DateTime? _parseServerDate(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;

    try {
      final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
      final hasTimezone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(normalized);

      // السيرفر يرجع الوقت غالباً بصيغة UTC بدون Z، لذلك نضيفها حتى لا يظهر التعليق الجديد 3h.
      final dateText = hasTimezone ? normalized : '${normalized}Z';
      return DateTime.parse(dateText).toLocal();
    } catch (_) {
      try {
        return DateTime.parse(raw).toLocal();
      } catch (_) {
        return null;
      }
    }
  }

  DateTime? get parsedCreatedAt => _parseServerDate(createdAt);

  static List<_Comment> newestFirst(List<_Comment> comments) {
    final sorted = List<_Comment>.from(comments);
    sorted.sort((a, b) {
      final ad = a.parsedCreatedAt;
      final bd = b.parsedCreatedAt;
      if (ad != null && bd != null) {
        final byDate = bd.compareTo(ad);
        if (byDate != 0) return byDate;
      } else if (ad != null) {
        return -1;
      } else if (bd != null) {
        return 1;
      }
      return b.id.compareTo(a.id);
    });
    return sorted;
  }

  String get timeAgo {
    if (createdAt.isEmpty) return '';
    try {
      final dt = parsedCreatedAt;
      if (dt == null) return createdAt.split(' ').first;
      var diff = DateTime.now().difference(dt);
      if (diff.isNegative) diff = Duration.zero;
      if (diff.inSeconds < 10) return 'الآن';
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
    super.key,
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

class _PostCardState extends State<_PostCard> with AutomaticKeepAliveClientMixin {
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
  final GlobalKey<_PostVideoPlayerState> _videoKey = GlobalKey<_PostVideoPlayerState>();
  VoidCallback? _realtimeBusListener;

  @override
  bool get wantKeepAlive => widget.post.videoUrl != null;

  @override
  void initState() {
    super.initState();

_realtimeBusListener = _onRealtimeUpdate;
_PostRealtimeBus.tick.addListener(_realtimeBusListener!);
_onRealtimeUpdate();

    _loadCommentCount();
    _loadLikes();

    // تحديث رقم التعليقات والإعجابات كل 5 ثواني بدون تحديث الصفحة
    _startCommentsPolling();
  }

  void _onRealtimeUpdate() {
    if (!mounted) return;

    final snap = _PostRealtimeBus.snapshot(widget.post.id);
    if (snap == null) return;

    bool changed = false;
    int nextLikesCount = _likesCount;
    bool nextLiked = _liked;
    List<_Comment> nextComments = _comments;
    bool nextCommentsLoaded = _commentsLoaded;

    if (snap.likesCount != null && snap.likesCount != _likesCount) {
      nextLikesCount = snap.likesCount!;
      changed = true;
    }

    if (snap.liked != null && snap.liked != _liked) {
      nextLiked = snap.liked!;
      changed = true;
    }

    if (snap.comments != null &&
        _PostRealtimeBus.commentsChanged(_comments, snap.comments!)) {
      nextComments = _Comment.newestFirst(snap.comments!);
      nextCommentsLoaded = true;
      changed = true;
    }

    if (!changed) return;

    setState(() {
      _likesCount = nextLikesCount;
      _liked = nextLiked;
      _comments = nextComments;
      _commentsLoaded = nextCommentsLoaded;
    });
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
          final nextLikesCount =
              int.tryParse('${data['likes_count'] ?? 0}') ?? 0;
          final nextLiked = data['liked'] == true;

          if (nextLikesCount != _likesCount || nextLiked != _liked) {
            setState(() {
              _likesCount = nextLikesCount;
              _liked = nextLiked;
            });
          }

          _PostRealtimeBus.publishLikes(
            widget.post.id,
            likesCount: nextLikesCount,
            liked: nextLiked,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _silentReloadLikes() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email ?? '';
      final uri = Uri.parse(_getLikesApi).replace(queryParameters: {
        'post_id': '${widget.post.id}',
        if (email.isNotEmpty) 'user_email': email,
      });

      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (!mounted || res.statusCode != 200) return;

      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map || data['success'] != true) return;

      final nextLikesCount =
          int.tryParse('${data['likes_count'] ?? _likesCount}') ?? _likesCount;
      final nextLiked = data['liked'] == true;

      if (nextLikesCount != _likesCount || nextLiked != _liked) {
        setState(() {
          _likesCount = nextLikesCount;
          _liked = nextLiked;
        });
      }

      _PostRealtimeBus.publishLikes(
        widget.post.id,
        likesCount: nextLikesCount,
        liked: nextLiked,
      );
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

    _PostRealtimeBus.publishLikes(
      widget.post.id,
      likesCount: _likesCount,
      liked: _liked,
    );

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
          final nextLiked = data['liked'] == true;
          final nextLikesCount =
              int.tryParse('${data['likes_count'] ?? _likesCount}') ??
                  _likesCount;

          setState(() {
            _liked = nextLiked;
            _likesCount = nextLikesCount;
          });

          _PostRealtimeBus.publishLikes(
            widget.post.id,
            likesCount: nextLikesCount,
            liked: nextLiked,
          );
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
    final listener = _realtimeBusListener;
if (listener != null) {
  _PostRealtimeBus.tick.removeListener(listener);
}
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCommentCount() async {
    await _loadComments();
  }

void _startCommentsPolling() {
  _commentsPollingTimer?.cancel();

  _commentsPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
    _silentReloadLikes();
    _silentReloadComments();
  });
}

void _stopCommentsPolling() {
  _commentsPollingTimer?.cancel();
  _commentsPollingTimer = null;
}

String _commentsFingerprint(List<_Comment> list) {
  return list
      .map((c) => '${c.id}|${c.text}|${c.createdAt}')
      .join('::');
}

void _applyComments(List<_Comment> loaded, {bool force = false}) {
  if (!mounted) return;

  final oldFingerprint = _commentsFingerprint(_comments);
  final newFingerprint = _commentsFingerprint(loaded);

  if (!force && oldFingerprint == newFingerprint && _commentsLoaded) {
    return;
  }

  final safeLoaded = _Comment.newestFirst(loaded);

  setState(() {
    _comments = safeLoaded;
    _commentsLoaded = true;
  });

  _PostRealtimeBus.publishComments(widget.post.id, safeLoaded);
}

Future<void> _silentReloadComments() async {
  try {
    final res = await http.get(
      Uri.parse('$_commentsApi?post_id=${widget.post.id}'),
    ).timeout(const Duration(seconds: 10));

    if (!mounted || res.statusCode != 200) return;

    final body = utf8.decode(res.bodyBytes);
    final data = jsonDecode(body);

    List<_Comment> loaded = [];

    if (data is List) {
      loaded = data
          .whereType<Map>()
          .map((e) => _Comment.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else if (data is Map && data['comments'] is List) {
      loaded = (data['comments'] as List)
          .whereType<Map>()
          .map((e) => _Comment.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    _applyComments(loaded);
  } catch (_) {}
}

Future<void> _loadComments() async {
  if (_loadingComments) return;

  setState(() => _loadingComments = true);

  try {
    final res = await http.get(
      Uri.parse('$_commentsApi?post_id=${widget.post.id}'),
    ).timeout(const Duration(seconds: 15));

    if (!mounted || res.statusCode != 200) return;

    final body = utf8.decode(res.bodyBytes);
    final data = jsonDecode(body);

    List<_Comment> loaded = [];

    if (data is List) {
      loaded = data
          .whereType<Map>()
          .map((e) => _Comment.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else if (data is Map && data['comments'] is List) {
      loaded = (data['comments'] as List)
          .whereType<Map>()
          .map((e) => _Comment.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    _applyComments(loaded, force: true);
  } catch (_) {
  } finally {
    if (mounted) setState(() => _loadingComments = false);
  }
}

  Future<void> _sendComment() async {
    if (_sendingComment) return;
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
          _PostRealtimeBus.publishComments(widget.post.id, _comments);
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
    final existingVideoController =
        _videoKey.currentState?.takeControllerForDetail();

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: _PostDetailPage(
            post: widget.post,
            isDark: widget.isDark,
            existingController: existingVideoController,
            isSupervisor: widget.isSupervisor,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    ).then((_) {
      if (mounted) {
        _videoKey.currentState?.releaseControllerFromDetail();
      }
    });
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
  if (!mounted) return;

  _sheetOpen = true;
  bool sheetAlive = true;
  Timer? sheetRefreshTimer;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: false,
    barrierColor: Colors.black.withOpacity(0.35),
    builder: (_) => StatefulBuilder(
      builder: (context, setSheetState) {
        void safeSheetSetState() {
          if (!_sheetOpen || !sheetAlive || !mounted) return;
          setSheetState(() {});
        }

        sheetRefreshTimer ??= Timer.periodic(
          const Duration(seconds: 5),
          (_) async {
            if (!_sheetOpen || !sheetAlive || !mounted) return;

            await _silentReloadLikes();

            if (!_sheetOpen || !sheetAlive || !mounted) return;

            await _silentReloadComments();

            if (!_sheetOpen || !sheetAlive || !mounted) return;

            safeSheetSetState();
          },
        );

        return _CommentsBottomSheet(
          post: widget.post,
          isDark: widget.isDark,
          comments: _comments,
          loadingComments: _loadingComments,
          commentsLoaded: _commentsLoaded,
          commentCtrl: _commentCtrl,
          sendingComment: _sendingComment,
          autoFocus: autoFocus,
          isSupervisor: widget.isSupervisor,

          onSend: () async {
            await _sendComment();

            if (!mounted || !sheetAlive || !_sheetOpen) return;

            setState(() {});
            safeSheetSetState();
          },

          onLoginTap: _showLoginSheet,

          onReload: () async {
            await _loadComments();

            if (!mounted || !sheetAlive || !_sheetOpen) return;

            safeSheetSetState();
          },

          onEdit: (id, newText) async {
            await _editComment(id, newText);

            if (!mounted || !sheetAlive || !_sheetOpen) return;

            setState(() {});
            safeSheetSetState();
          },

          onDelete: (id) async {
            await _deleteComment(id);

            if (!mounted || !sheetAlive || !_sheetOpen) return;

            setState(() {});
            safeSheetSetState();
          },
        );
      },
    ),
  ).whenComplete(() {
    sheetAlive = false;
    _sheetOpen = false;
    sheetRefreshTimer?.cancel();
    sheetRefreshTimer = null;
  });
}
  @override
  Widget build(BuildContext context) {
    super.build(context);
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
                key: _videoKey,
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
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _toggleLike();
                    },
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
                    onTap: () => _sharePublicationPost(context, widget.post),
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
  showSendButton: false,
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
  final Future<void> Function() onSend;
  final FocusNode? focusNode;
  final bool showSendButton;

  const _CommentInputBox({
    required this.isDark,
    required this.user,
    required this.controller,
    required this.sending,
    required this.onSend,
    this.focusNode,
    this.showSendButton = true,
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
          padding: const EdgeInsets.only(bottom: 2),
          child: CircleAvatar(
            radius: 21,
            backgroundImage:
                user.photoURL != null ? NetworkImage(user.photoURL!) : null,
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
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final canShowSend =
                    showSendButton && (value.text.trim().isNotEmpty || sending);

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
AnimatedSwitcher(
  duration: const Duration(milliseconds: 280),
  reverseDuration: const Duration(milliseconds: 220),
  switchInCurve: Curves.easeOutCubic,
  switchOutCurve: Curves.easeInCubic,
  layoutBuilder: (currentChild, previousChildren) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: <Widget>[
        ...previousChildren,
        if (currentChild != null) currentChild,
      ],
    );
  },
  transitionBuilder: (child, animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(
          begin: 0.18,
          end: 1.0,
        ).animate(curved),
        alignment: Alignment.center,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: child,
        ),
      ),
    );
  },
                      child: canShowSend
                          ? Padding(
                              key: const ValueKey('comment-send-button'),
                              padding: const EdgeInsets.only(
                                  left: 9, right: 6, bottom: 7),
                              child: GestureDetector(
                                onTap: sending
                                    ? null
                                    : () {
                                        HapticFeedback.selectionClick();
                                        onSend();
                                      },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOutCubic,
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
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.send_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                ),
                              ),
                            )
                          : const SizedBox(
                              key: ValueKey('comment-send-empty'),
                              width: 0,
                              height: 42,
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
                            fontWeight: FontWeight.w400,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                );
              },
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
  final Future<void> Function() onSend;
  final VoidCallback onLoginTap;
  final Future<void> Function() onReload;
  final Future<void> Function(int, String) onEdit;
  final Future<void> Function(int) onDelete;
  final bool autoFocus;
  final bool isSupervisor;

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
    required this.isSupervisor,
  });

  @override
  State<_CommentsBottomSheet> createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends State<_CommentsBottomSheet> {
  static const gold = Color(0xFFD4A017);

  static const double _minSheetSize = 0.65;
  static const double _normalSheetSize = 0.70;
  static const double _keyboardSheetSize = 0.85;
  static const double _maxSheetSize = 1.0;
  static const List<double> _sheetSnapSizes = [
    _minSheetSize,
    _normalSheetSize,
    _keyboardSheetSize,
    _maxSheetSize,
  ];

  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _commentsListController = ScrollController();
  bool _localSendingComment = false;

bool _commentsListSheetDragging = false;
double _sheetDragDownOffset = 0;

int? _newAnimatedCommentId;
  bool _scrollToNewCommentAfterSend = false;

  // FIX_V4_HEADER_CONTROLS_REAL_SHEET_HEIGHT
  // تركنا DraggableScrollableSheet نهائياً لأن رأس النافذة لازم يتحكم بالحجم وحده.
  double _sheetSize = _normalSheetSize;
  double _headerDragTotalDelta = 0;
  bool _headerDragging = false;

  void _beginHeaderSheetDrag() {
    _headerDragTotalDelta = 0;
    if (mounted) {
      setState(() => _headerDragging = true);
    }
  }

  void _dragHeaderSheetByDelta(double deltaDy) {
    if (!mounted) return;

    _headerDragTotalDelta += deltaDy;

    final media = MediaQuery.of(context);
    final usableHeight = (media.size.height - media.viewPadding.top)
        .clamp(1.0, double.infinity)
        .toDouble();

   
    const double dragSensitivity = 0.75;

    final nextSize = (_sheetSize - (deltaDy / usableHeight) * dragSensitivity)
        .clamp(_minSheetSize, _maxSheetSize)
        .toDouble();

    setState(() {
      _sheetSize = nextSize;
    });
  }

  void _endHeaderSheetDrag() {
    if (!mounted) return;

    final totalDelta = _headerDragTotalDelta;
    _headerDragTotalDelta = 0;

    final currentSize = _sheetSize;
    double targetSize;

    if (totalDelta.abs() < 8) {
      targetSize = _sheetSnapSizes.reduce((a, b) {
        return (a - currentSize).abs() < (b - currentSize).abs() ? a : b;
      });
    } else if (totalDelta < 0) {
      // سحب للأعلى: اصعد للمرحلة الأعلى.
      targetSize = _sheetSnapSizes.firstWhere(
        (size) => size > currentSize + 0.005,
        orElse: () => _maxSheetSize,
      );
    } else {
      // سحب للأسفل: انزل للمرحلة الأقل.
      targetSize = _sheetSnapSizes.reversed.firstWhere(
        (size) => size < currentSize - 0.005,
        orElse: () => _minSheetSize,
      );
    }

    setState(() {
      _headerDragging = false;
      _sheetSize = targetSize;
    });
  }
  void _scrollToNewestComment() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_commentsListController.hasClients) return;

      _commentsListController.animateTo(
        _commentsListController.position.minScrollExtent,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
      );
    });
  }

bool _commentsListIsAtTop() {
  if (!_commentsListController.hasClients) return false;

  final position = _commentsListController.position;
  return position.pixels <= position.minScrollExtent + 18.0;
}

void _beginCommentsListSheetDrag() {
  if (_commentsListSheetDragging) return;

  FocusScope.of(context).unfocus();

  setState(() {
    _commentsListSheetDragging = true;
    _headerDragging = true;
    _sheetDragDownOffset = 0;
  });
}

void _dragCommentsListSheetByDelta(double deltaDy) {
  if (!mounted) return;

  if (deltaDy <= 0) return;

  if (!_commentsListSheetDragging) {
    _beginCommentsListSheetDrag();
  }

  final media = MediaQuery.of(context);
  final usableHeight = (media.size.height - media.viewPadding.top)
      .clamp(1.0, double.infinity)
      .toDouble();

  final maxOffset = usableHeight * 0.95;

  setState(() {
    _sheetDragDownOffset =
        (_sheetDragDownOffset + deltaDy).clamp(0.0, maxOffset).toDouble();
  });
}

void _endCommentsListSheetDrag() {
  if (!_commentsListSheetDragging) return;

  final shouldClose = _sheetDragDownOffset > 85;

  if (shouldClose) {
    Navigator.of(context).maybePop();
    return;
  }

  if (!mounted) return;

  setState(() {
    _commentsListSheetDragging = false;
    _headerDragging = false;
    _sheetDragDownOffset = 0;
  });
}

  @override
  void initState() {
    super.initState();

    if (!widget.commentsLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await widget.onReload();
      });
    }

    if (widget.autoFocus) {
      _sheetSize = _keyboardSheetSize;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _inputFocusNode.requestFocus();
        });
      });
    }
  }

  @override
  void didUpdateWidget(covariant _CommentsBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldIds = oldWidget.comments.map((c) => c.id).toSet();

    final newComments = widget.comments
        .where((c) => c.text.isNotEmpty && !oldIds.contains(c.id))
        .toList();

    if (newComments.isEmpty) return;

    final newest = _Comment.newestFirst(newComments).first;

    setState(() {
      _newAnimatedCommentId = newest.id;
    });

    if (_scrollToNewCommentAfterSend) {
      _scrollToNewCommentAfterSend = false;
      _scrollToNewestComment();
    }
  }

  @override
  void dispose() {
    _inputFocusNode.dispose();
    _commentsListController.dispose();
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

    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;
    final usableHeight = (media.size.height - media.viewPadding.top)
        .clamp(1.0, double.infinity)
        .toDouble();
    final effectiveSheetSize = keyboardOpen && _sheetSize < _keyboardSheetSize
        ? _keyboardSheetSize
        : _sheetSize;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: const SizedBox.expand(),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: () => FocusScope.of(context).unfocus(),
  onVerticalDragUpdate: (details) {
    if (details.delta.dy > 6) {
      FocusScope.of(context).unfocus();
    }
  },
child: AnimatedContainer(
duration: _headerDragging
    ? Duration.zero
    : const Duration(milliseconds: 220),
curve: Curves.easeOutCubic,
transform: Matrix4.translationValues(0, _sheetDragDownOffset, 0),
transformAlignment: Alignment.bottomCenter,
width: double.infinity,
height: usableHeight * effectiveSheetSize,
            decoration: BoxDecoration(
              color: sheetBg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
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
Listener(
  behavior: HitTestBehavior.opaque,
  onPointerDown: (_) => _beginHeaderSheetDrag(),
  onPointerMove: (event) {
    if (_commentsListSheetDragging || event.delta.dy > 0) {
      _dragCommentsListSheetByDelta(event.delta.dy);
    } else {
      _dragHeaderSheetByDelta(event.delta.dy);
    }
  },
  onPointerUp: (_) {
    if (_commentsListSheetDragging) {
      _endCommentsListSheetDrag();
    } else {
      _endHeaderSheetDrag();
    }
  },
  onPointerCancel: (_) {
    if (_commentsListSheetDragging) {
      _endCommentsListSheetDrag();
    } else {
      _endHeaderSheetDrag();
    }
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
                            const SizedBox(width: 22),
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
                            color: gold,
                            strokeWidth: 2.5,
                          ),
                        )
: widget.comments.isEmpty
    ? Listener(
        behavior: HitTestBehavior.translucent,
        onPointerMove: (event) {
          if (_commentsListSheetDragging || event.delta.dy > 0) {
            _dragCommentsListSheetByDelta(event.delta.dy);
          }
        },
        onPointerUp: (_) {
          if (_commentsListSheetDragging) {
            _endCommentsListSheetDrag();
          }
        },
        onPointerCancel: (_) {
          if (_commentsListSheetDragging) {
            _endCommentsListSheetDrag();
          }
        },
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 44,
                color: gold.withOpacity(0.4),
              ),
              const SizedBox(height: 12),
              Text(
                'لا توجد تعليقات بعد\nكن أول من يعلّق!',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: textSub,
                  fontSize: 14,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
      )
: Listener(
    behavior: HitTestBehavior.translucent,
    onPointerMove: (event) {
      if (_commentsListSheetDragging ||
          (event.delta.dy > 0 && _commentsListIsAtTop())) {
        _dragCommentsListSheetByDelta(event.delta.dy);
      }
    },
    onPointerUp: (_) {
      if (_commentsListSheetDragging) {
        _endCommentsListSheetDrag();
      }
    },
    onPointerCancel: (_) {
      if (_commentsListSheetDragging) {
        _endCommentsListSheetDrag();
      }
    },
    child: ListView.separated(
  controller: _commentsListController,
  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
  primary: false,
                                physics: _commentsListSheetDragging
                                    ? const NeverScrollableScrollPhysics()
                                    : const BouncingScrollPhysics(
                                        parent: AlwaysScrollableScrollPhysics(),
                                      ),
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                itemCount: widget.comments.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 28,
                                  color: isDark
                                      ? const Color.fromARGB(1, 49, 49, 49)
                                          .withOpacity(0.05)
                                      : const Color.fromARGB(6, 190, 190, 190)
                                          .withOpacity(0.06),
                                ),
                                itemBuilder: (context, i) {
                                  final c = widget.comments[i];

                                  if (c.text.isEmpty) {
                                    return const SizedBox.shrink();
                                  }

                                  final animateNew =
                                      _newAnimatedCommentId == c.id;

                                  return TweenAnimationBuilder<double>(
                                    key: ValueKey(
                                      'comment_anim_${c.id}_$animateNew',
                                    ),
                                    tween: Tween<double>(
                                      begin: animateNew ? 0.0 : 1.0,
                                      end: 1.0,
                                    ),
                                    duration: animateNew
                                        ? const Duration(milliseconds: 620)
                                        : Duration.zero,
                                    curve: Curves.easeOutCubic,
                                    builder: (context, value, child) {
                                      final safeValue =
                                          value.clamp(0.0, 1.0);

                                      return Opacity(
                                        opacity: safeValue,
                                        child: Transform.translate(
                                          offset: Offset(
                                            0,
                                            (1 - safeValue) * 34,
                                          ),
                                          child: Transform.scale(
                                            scale:
                                                0.94 + (safeValue * 0.06),
                                            alignment: Alignment.bottomRight,
                                            child: child,
                                          ),
                                        ),
                                      );
                                    },
                                    child: _CommentTile(
                                      comment: c,
                                      isDark: isDark,
                                      onEdit: widget.onEdit,
                                      onDelete: widget.onDelete,
                                      isSupervisor: widget.isSupervisor,
                                    ),
                                  );
                                },
                              ),
                            ),
                ),

                // Input box
                Divider(height: 1, thickness: 0.5, color: dividerColor),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    10,
                    12,
                    28 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: currentUser != null
                      ? _CommentInputBox(
                          isDark: isDark,
                          user: currentUser,
                          controller: widget.commentCtrl,
                          sending: widget.sendingComment || _localSendingComment,
                          focusNode: _inputFocusNode,
                          onSend: () async {
                            if (_localSendingComment || widget.sendingComment) return;
                            _scrollToNewCommentAfterSend = true;

                            setState(() => _localSendingComment = true);
                            try {
                              await widget.onSend();
                            } finally {
                              if (mounted) {
                                setState(() => _localSendingComment = false);
                              }
                            }

                            if (!mounted) return;

                            setState(() {});
                            _scrollToNewestComment();
                          },
                        )
                      : _LockedCommentBox(
                          isDark: isDark,
                          onLoginTap: widget.onLoginTap,
                        ),
                ),
              ],
            ),
          ),
        ),
        
      ),],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Comment Tile (used inside sheet)
// ─────────────────────────────────────────────────────────────────────────────

class _SoloEmojiGlowText extends StatefulWidget {
  final String text;
  final Color color;
  final double fontSize;

  const _SoloEmojiGlowText({
    required this.text,
    required this.color,
    required this.fontSize,
  });

  @override
  State<_SoloEmojiGlowText> createState() => _SoloEmojiGlowTextState();
}

class _SoloEmojiGlowTextState extends State<_SoloEmojiGlowText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _glow;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )..repeat(reverse: true);

    _glow = Tween<double>(begin: 3, end: 14).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _scale = Tween<double>(begin: 0.97, end: 1.06).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scale.value,
          child: Text(
            widget.text,
            textDirection: TextDirection.rtl,
            style: DefaultTextStyle.of(context).style.copyWith(
              color: widget.color,
              fontSize: widget.fontSize,
              height: 1.15,
              shadows: [
                Shadow(
                  color: const Color(0xFFFFD54F).withOpacity(0.45),
                  blurRadius: _glow.value,
                ),
                Shadow(
                  color: const Color(0xFFFFA000).withOpacity(0.25),
                  blurRadius: _glow.value * 1.6,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CommentTile extends StatefulWidget {
  final _Comment comment;
  final bool isDark;
  final Future<void> Function(int, String)? onEdit;
  final Future<void> Function(int)? onDelete;
  final bool isSupervisor;

  const _CommentTile({
    required this.comment,
    required this.isDark,
    this.onEdit,
    this.onDelete,
    this.isSupervisor = false,
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
    final canEditComment = _isOwner;
    final canDeleteComment = _isOwner || widget.isSupervisor;

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
: Builder(
    builder: (context) {
      bool isEmojiRune(int rune) {
        return (rune >= 0x1F300 && rune <= 0x1FAFF) ||
            (rune >= 0x2600 && rune <= 0x27BF) ||
            (rune >= 0x1F1E6 && rune <= 0x1F1FF) ||
            rune == 0x200D ||
            rune == 0xFE0F;
      }

      bool isEmojiBaseRune(int rune) {
        return ((rune >= 0x1F300 && rune <= 0x1FAFF) ||
                (rune >= 0x2600 && rune <= 0x27BF) ||
                (rune >= 0x1F1E6 && rune <= 0x1F1FF)) &&
            rune != 0xFE0F &&
            rune != 0x200D;
      }

      final trimmedText = widget.comment.text.trim();

      final onlyEmojiComment = trimmedText.isNotEmpty &&
          trimmedText.runes.every((rune) {
            final char = String.fromCharCode(rune);
            return char.trim().isEmpty || isEmojiRune(rune);
          });

      final emojiBaseCount = trimmedText.runes
          .where((rune) => isEmojiBaseRune(rune))
          .length;

      final singleEmojiOnly = onlyEmojiComment && emojiBaseCount == 1;

      if (singleEmojiOnly) {
        return _SoloEmojiGlowText(
          text: trimmedText,
          color: textPrimary,
          fontSize: 45,
        );
      }

      return RichText(
        textDirection: TextDirection.rtl,
        text: TextSpan(
          children: widget.comment.text.runes.map((rune) {
            final char = String.fromCharCode(rune);
            final isEmoji = isEmojiRune(rune);

            return TextSpan(
              text: char,
              style: DefaultTextStyle.of(context).style.copyWith(
                color: textPrimary,
                fontSize: onlyEmojiComment
                    ? 45
                    : isEmoji
                        ? 18
                        : 13.5,
                height: onlyEmojiComment ? 1.25 : 1.6,
              ),
            );
          }).toList(),
        ),
      );
    },
  ),

              // أزرار التعديل لصاحب التعليق، والحذف لصاحب التعليق أو المشرف
              if (canEditComment || canDeleteComment) ...[
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
                      if (canEditComment) ...[
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
                      ],
                      if (canEditComment && canDeleteComment)
                        const SizedBox(width: 12),
                      if (canDeleteComment)
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
      await FirebaseAuth.instance.currentUser?.reload();
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

return GestureDetector(
  behavior: HitTestBehavior.translucent,
  onVerticalDragUpdate: (details) {
    if (details.delta.dy > 6) {
      FocusScope.of(context).unfocus();
    }
  },
  child: Padding(
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
  final bool? isSupervisor;

  const _PostDetailPage({
    required this.post,
    required this.isDark,
    this.existingController,
    this.isSupervisor,
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
  late final VoidCallback _globalMuteListener;
  bool _isDraggingSlider = false;

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void initState() {
    super.initState();

    _globalMuteListener = () {
      _GlobalVideoMute.applyTo(widget.controller);
      if (mounted) setState(() {});
    };

    _GlobalVideoMute.muted.addListener(_globalMuteListener);
    _GlobalVideoMute.applyTo(widget.controller);
  }

  @override
  void dispose() {
    _GlobalVideoMute.muted.removeListener(_globalMuteListener);
    super.dispose();
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
  _GlobalVideoMute.toggle();
},
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
child: ValueListenableBuilder<bool>(
  valueListenable: _GlobalVideoMute.muted,
  builder: (_, muted, __) {
    return Icon(
      muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
      color: Colors.white,
      size: 17,
    );
  },
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
                        trackShape: const _FullWidthRectSliderTrackShape(),
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
  VoidCallback? _realtimeBusListener;

  String get _cacheKey => 'post_detail_${widget.post.id}';

  @override
  void initState() {
    super.initState();

_realtimeBusListener = _onRealtimeUpdate;
_PostRealtimeBus.tick.addListener(_realtimeBusListener!);
_onRealtimeUpdate();

    _loadFromCacheThenNetwork();
    if (widget.existingController != null) {
      _videoController = widget.existingController;
      _videoOwned = false;
    }

    // تحديث فوري ناعم كل 5 ثواني للإعجابات والتعليقات بدون ريفرش
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
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
          _comments = _Comment.newestFirst(
            rawComments
                .whereType<Map>()
                .map((e) => _Comment.fromJson(Map<String, dynamic>.from(e)))
                .toList(),
          );
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

  List<_Comment> _parseCommentsPayload(dynamic data) {
    if (data is List) {
      return _Comment.newestFirst(
        data
            .whereType<Map>()
            .map((e) => _Comment.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    }

    if (data is Map && data['comments'] is List) {
      return _Comment.newestFirst(
        (data['comments'] as List)
            .whereType<Map>()
            .map((e) => _Comment.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    }

    return [];
  }

  void _applyDetailComments(
    List<_Comment> fresh, {
    bool force = false,
    bool publish = true,
  }) {
    if (!mounted) return;

    if (!force && !_PostRealtimeBus.commentsChanged(_comments, fresh)) {
      return;
    }

    final safeFresh = _Comment.newestFirst(fresh);
    setState(() {
      _comments = safeFresh;
      _commentsLoaded = true;
    });

    _saveToCache();
    if (publish) {
      _PostRealtimeBus.publishComments(widget.post.id, safeFresh);
    }
  }

  void _onRealtimeUpdate() {
    if (!mounted) return;

    final snap = _PostRealtimeBus.snapshot(widget.post.id);
    if (snap == null) return;

    bool changed = false;
    int nextLikesCount = _likesCount;
    bool nextLiked = _liked;
    List<_Comment> nextComments = _comments;
    bool nextCommentsLoaded = _commentsLoaded;

    if (snap.likesCount != null && snap.likesCount != _likesCount) {
      nextLikesCount = snap.likesCount!;
      changed = true;
    }

    if (snap.liked != null && snap.liked != _liked) {
      nextLiked = snap.liked!;
      changed = true;
    }

    if (snap.comments != null &&
        _PostRealtimeBus.commentsChanged(_comments, snap.comments!)) {
      nextComments = _Comment.newestFirst(snap.comments!);
      nextCommentsLoaded = true;
      changed = true;
    }

    if (!changed) return;

    setState(() {
      _likesCount = nextLikesCount;
      _liked = nextLiked;
      _comments = nextComments;
      _commentsLoaded = nextCommentsLoaded;
      _loadingComments = false;
    });

    _saveToCache();
  }

  // تحديث صامت كل 5 ثواني — بدون loading indicator
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
          final nextLiked = likeData['liked'] == true;
          final nextLikesCount =
              int.tryParse('${likeData['likes_count'] ?? _likesCount}') ??
                  _likesCount;

          if (nextLiked != _liked || nextLikesCount != _likesCount) {
            setState(() {
              _liked = nextLiked;
              _likesCount = nextLikesCount;
            });
            _saveToCache();
          }

          _PostRealtimeBus.publishLikes(
            widget.post.id,
            likesCount: nextLikesCount,
            liked: nextLiked,
          );
        }
      }

      // تحديث التعليقات
      final commentsRes = await http.get(
        Uri.parse('$_commentsApi?post_id=${widget.post.id}'),
      ).timeout(const Duration(seconds: 10));
      if (commentsRes.statusCode == 200 && mounted) {
        final commentsData = jsonDecode(utf8.decode(commentsRes.bodyBytes));
        final fresh = _parseCommentsPayload(commentsData);
        _applyDetailComments(fresh);
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
          final nextLikesCount =
              int.tryParse('${data['likes_count'] ?? 0}') ?? 0;
          final nextLiked = data['liked'] == true;

          if (nextLikesCount != _likesCount || nextLiked != _liked) {
            setState(() {
              _likesCount = nextLikesCount;
              _liked = nextLiked;
            });
            await _saveToCache();
          }

          _PostRealtimeBus.publishLikes(
            widget.post.id,
            likesCount: nextLikesCount,
            liked: nextLiked,
          );
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

    _saveToCache();
    _PostRealtimeBus.publishLikes(
      widget.post.id,
      likesCount: _likesCount,
      liked: _liked,
    );

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
          final nextLiked = data['liked'] == true;
          final nextLikesCount =
              int.tryParse('${data['likes_count'] ?? _likesCount}') ??
                  _likesCount;

          setState(() {
            _liked = nextLiked;
            _likesCount = nextLikesCount;
          });

          _saveToCache();
          _PostRealtimeBus.publishLikes(
            widget.post.id,
            likesCount: nextLikesCount,
            liked: nextLiked,
          );
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
    final listener = _realtimeBusListener;
if (listener != null) {
  _PostRealtimeBus.tick.removeListener(listener);
}
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
        final fresh = _parseCommentsPayload(data);
        _applyDetailComments(fresh, force: true);
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

Future<void> _sendComment() async {
    if (_sendingComment) return;
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
    final isSupervisor = widget.isSupervisor ?? _isCurrentUserSupervisor();

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null &&
            details.primaryVelocity!.abs() > 300) {
          HapticFeedback.lightImpact();
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
        leadingWidth: 112,
        leading: GestureDetector(
          onTap: () => _sharePublicationPost(context, p),
          child: Container(
            margin: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: gold.withOpacity(0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: gold.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
        actions: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
              decoration: BoxDecoration(
                color: gold.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_forward_ios_rounded,
                  color: gold, size: 18),
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
  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
  physics: const BouncingScrollPhysics(),
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
                              isSupervisor: isSupervisor,
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
                12, 10, 12, MediaQuery.of(context).padding.bottom + 18),
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
  final bool isSupervisor;

  const _CommentBubble({
    required this.comment,
    required this.isDark,
    this.onEdit,
    this.onDelete,
    this.isSupervisor = false,
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
    final canEditComment = _isOwner;
    final canDeleteComment = _isOwner || widget.isSupervisor;

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
                if (canEditComment || canDeleteComment) ...[
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
                        if (canEditComment) ...[
                          GestureDetector(
                            onTap: () => setState(() => _editing = true),
                            child: Icon(Icons.edit_rounded, color: const Color.fromARGB(255, 104, 107, 109), size: 17),
                          ),
                        ],
                        if (canEditComment && canDeleteComment)
                          const SizedBox(width: 6),
                        if (canDeleteComment)
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
  final GlobalKey _descriptionFieldKey = GlobalKey();

  void _hideKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _hideKeyboardIfTapOutsideDescription(PointerDownEvent event) {
    final boxContext = _descriptionFieldKey.currentContext;
    if (boxContext == null) {
      _hideKeyboard();
      return;
    }

    final renderBox = boxContext.findRenderObject();
    if (renderBox is! RenderBox) {
      _hideKeyboard();
      return;
    }

    final topLeft = renderBox.localToGlobal(Offset.zero);
    final fieldRect = topLeft & renderBox.size;
    if (!fieldRect.contains(event.position)) {
      _hideKeyboard();
    }
  }

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

    final media = MediaQuery.of(context);
    final keyboardHeight = media.viewInsets.bottom;
    final keyboardVisible = keyboardHeight > 0;
    final double? sheetHeight = keyboardVisible
        ? (media.size.height * 0.90 - keyboardHeight)
            .clamp(360.0, media.size.height * 0.90)
            .toDouble()
        : null;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _hideKeyboardIfTapOutsideDescription,
      onPointerMove: (event) {
        if (event.delta.dy > 4) _hideKeyboard();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (details) {
          if (details.delta.dy > 2) _hideKeyboard();
        },
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: keyboardHeight),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            height: sheetHeight,
            decoration: BoxDecoration(
              color: sheetBg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize:
                    keyboardVisible ? MainAxisSize.max : MainAxisSize.min,
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
              Flexible(
                fit: keyboardVisible ? FlexFit.tight : FlexFit.loose,
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const BouncingScrollPhysics(),
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
                      key: _descriptionFieldKey,
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
                  ],),
                ),
              ),
            ],
            
          ),
        ),
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
    super.key,
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
                          trackShape: const _FullWidthRectSliderTrackShape(),
thumbShape: _isDraggingSlider
    ? const RoundSliderThumbShape(enabledThumbRadius: 7)
    : SliderComponentShape.noThumb,
overlayShape: _isDraggingSlider
    ? const RoundSliderOverlayShape(overlayRadius: 14)
    : SliderComponentShape.noOverlay,
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
  VideoPlayerController? _creatingController;

  bool _initialized = false;
  Uint8List? _videoThumbBytes;
  bool _showLoadingOverlay = true;

  bool _videoLoadStarted = false;
  bool _videoInitInProgress = false;
  bool _cancelVideoInit = false;

  Timer? _videoStartTimer;

  late final VoidCallback _globalMuteListener;
  String get _videoId => 'post_video_${widget.post.id}_${widget.videoUrl.hashCode}';
  late final VoidCallback _activeVideoListener;

  bool _showControls = true;
  bool _disposed = false;
  bool _isDraggingSlider = false;
  bool _isTransferred = false;
  bool _userPaused = false;
  double _visibleFraction = 0.0;

  @override
  bool get wantKeepAlive => true;

  VideoPlayerController? takeControllerForDetail() {
    if (_controller == null || !_initialized || _videoInitInProgress) return null;

    if (mounted) {
      _safeSetState(() => _isTransferred = true);
    } else {
      _isTransferred = true;
    }

    _VisibleVideoCoordinator.clearActive();
    _VisibleVideoCoordinator.remove(_videoId);

    return _controller;
  }

  void releaseControllerFromDetail() {
    if (!mounted || _disposed) return;

    _safeSetState(() => _isTransferred = false);

    _VisibleVideoCoordinator.update(_videoId, _visibleFraction);
    _syncPlaybackWithVisibility();
  }

  @override
  void initState() {
    super.initState();

    _globalMuteListener = () {
      _GlobalVideoMute.applyTo(_controller);
      if (mounted && !_disposed) _safeSetState(() {});
    };

    _activeVideoListener = _syncPlaybackWithVisibility;

    _GlobalVideoMute.muted.addListener(_globalMuteListener);
    _VisibleVideoCoordinator.activeVideoId.addListener(_activeVideoListener);
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted || _disposed) return;

    try {
      setState(fn);
    } catch (e) {
      debugPrint('Safe setState ignored: $e');
    }
  }

  void _cancelPendingVideoStart() {
    try {
      _videoStartTimer?.cancel();
    } catch (_) {}
    _videoStartTimer = null;
  }

  void _safeDisposeController(VideoPlayerController? ctrl) {
    if (ctrl == null) return;

    // مهم: لا نرمي dispose مباشرة أثناء السكرول السريع.
    // بعض أجهزة iOS/Android تنهار إذا انحذف مشغل الفيديو وهو بعده يهيئ الـ texture.
    Future.delayed(const Duration(milliseconds: 450), () async {
      try {
        if (ctrl.value.isInitialized && ctrl.value.isPlaying) {
          await ctrl.pause();
        }
      } catch (e) {
        debugPrint('Safe pause before dispose ignored: $e');
      }

      try {
        await ctrl.dispose();
      } catch (e) {
        debugPrint('Safe video dispose ignored: $e');
      }
    });
  }

  Future<void> _safePlay() async {
    final ctrl = _controller;

    if (!mounted ||
        _disposed ||
        ctrl == null ||
        !ctrl.value.isInitialized ||
        _isTransferred ||
        _visibleFraction < 0.35) {
      return;
    }

    try {
      await ctrl.play();
    } catch (e) {
      debugPrint('Safe video play ignored: $e');
    }
  }

  Future<void> _safePause() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    try {
      await ctrl.pause();
    } catch (e) {
      debugPrint('Safe video pause ignored: $e');
    }
  }

  Future<void> _safeSeekTo(Duration position) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    try {
      await ctrl.seekTo(position);
    } catch (e) {
      debugPrint('Safe video seek ignored: $e');
    }
  }

  void _startVideoLoadIfNeeded() {
    if (_videoLoadStarted ||
        _videoInitInProgress ||
        _disposed ||
        !mounted ||
        _isTransferred) {
      return;
    }

    _cancelPendingVideoStart();

    // لا تبدأ تحميل الفيديو لمجرد أنه لمس طرف الشاشة.
    // ننتظر نصف ثانية تقريباً حتى نتأكد المستخدم فعلاً وقف عليه.
    _videoStartTimer = Timer(const Duration(milliseconds: 550), () {
      if (!mounted ||
          _disposed ||
          _isTransferred ||
          _visibleFraction < 0.45 ||
          _videoLoadStarted ||
          _videoInitInProgress) {
        return;
      }

      _videoLoadStarted = true;
      _cancelVideoInit = false;

      try {
        _generateVideoThumbnail();
      } catch (e) {
        debugPrint('Start thumbnail safe error: $e');
      }

      try {
        _initVideo();
      } catch (e) {
        debugPrint('Start video safe error: $e');
      }
    });
  }

  Future<void> _generateVideoThumbnail() async {
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: widget.videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 900,
        quality: 78,
        timeMs: 120,
      ).timeout(const Duration(seconds: 8));

      if (!mounted || _disposed || _cancelVideoInit) return;

      if (bytes != null && bytes.isNotEmpty) {
        _safeSetState(() {
          _videoThumbBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint('Video thumbnail safe error: $e');
    }
  }

  Widget _buildVideoLoadingPreview() {
    return Container(
      color: widget.isDark
          ? const Color(0xFF222222)
          : const Color(0xFFEFE7D8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_videoThumbBytes != null)
            Image.memory(
              _videoThumbBytes!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),

          Container(
            color: Colors.black.withOpacity(
              _videoThumbBytes != null ? 0.24 : 0.0,
            ),
          ),

          Center(
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(
                  color: gold,
                  strokeWidth: 2.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _initVideo() async {
    if (_videoInitInProgress ||
        _controller != null ||
        _disposed ||
        !mounted ||
        _visibleFraction < 0.45) {
      return;
    }

    _videoInitInProgress = true;
    _cancelVideoInit = false;

    VideoPlayerController? ctrl;

    try {
      ctrl = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      _creatingController = ctrl;

      await ctrl.initialize().timeout(const Duration(seconds: 20));

      if (!mounted ||
          _disposed ||
          _cancelVideoInit ||
          _controller != null ||
          _visibleFraction < 0.05) {
        _safeDisposeController(ctrl);
        return;
      }

      await ctrl.setLooping(true);
      await ctrl.setVolume(_GlobalVideoMute.volume);
      await ctrl.pause();

      if (!mounted || _disposed || _cancelVideoInit) {
        _safeDisposeController(ctrl);
        return;
      }

      _safeSetState(() {
        _controller = ctrl;
        _initialized = true;
        _showLoadingOverlay = true;
      });

      Future.delayed(const Duration(milliseconds: 650), () {
        if (mounted && !_disposed) {
          _safeSetState(() => _showLoadingOverlay = false);
        }
      });

      _syncPlaybackWithVisibility();
      _scheduleHideControls();
    } catch (e) {
      debugPrint('Video init safe error: $e');

      if (ctrl != null && ctrl != _controller) {
        _safeDisposeController(ctrl);
      }

      if (mounted && !_disposed) {
        _safeSetState(() {
          _initialized = false;
          _controller = null;
          _showLoadingOverlay = true;
        });
      }

      // خلي المستخدم يقدر يعيد المحاولة إذا رجع للفيديو.
      _videoLoadStarted = false;
    } finally {
      if (_creatingController == ctrl) {
        _creatingController = null;
      }

      _videoInitInProgress = false;
    }
  }

  void _syncPlaybackWithVisibility() {
    final ctrl = _controller;

    if (!mounted ||
        _disposed ||
        ctrl == null ||
        !_initialized ||
        !ctrl.value.isInitialized ||
        _isTransferred) {
      return;
    }

    final shouldPlay =
        _VisibleVideoCoordinator.activeVideoId.value == _videoId &&
        !_userPaused &&
        _visibleFraction >= 0.35;

    if (shouldPlay) {
      if (!ctrl.value.isPlaying) {
        _safePlay();
        _safeSetState(() {});
      }
    } else {
      if (ctrl.value.isPlaying) {
        _safePause();
        _safeSetState(() {});
      }
    }
  }

  void _scheduleHideControls() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_disposed) _safeSetState(() => _showControls = false);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelVideoInit = true;
    _cancelPendingVideoStart();

    try {
      _GlobalVideoMute.muted.removeListener(_globalMuteListener);
    } catch (_) {}

    try {
      _VisibleVideoCoordinator.activeVideoId.removeListener(_activeVideoListener);
      _VisibleVideoCoordinator.remove(_videoId);
    } catch (_) {}

    if (!_isTransferred) {
      final ctrl = _controller;
      _controller = null;
      _initialized = false;

      // لا نحذف _creatingController هنا وهو بعده يحمّل.
      // دالة _initVideo ستتولى التخلص منه بعد انتهاء/فشل initialize.
      if (!_videoInitInProgress) {
        _safeDisposeController(ctrl);
      } else {
        _safePause();
      }
    }

    super.dispose();
  }

  void _toggleMute() {
    _GlobalVideoMute.toggle();
  }

  void _onTapVideo() {
    _safeSetState(() => _showControls = true);
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

    final ctrl = _controller;

    if (!_initialized || ctrl == null || !ctrl.value.isInitialized || _disposed) {
      return VisibilityDetector(
        key: Key('${_videoId}_loader'),
        onVisibilityChanged: (info) {
          if (!mounted || _disposed || _isTransferred) return;

          _visibleFraction = info.visibleFraction;

          if (info.visibleFraction >= 0.45) {
            _startVideoLoadIfNeeded();
          } else {
            _cancelPendingVideoStart();

            // إذا الفيديو لم يبدأ بعد، لا نسمح ببداية تحميل قديمة.
            if (!_videoInitInProgress && !_initialized) {
              _cancelVideoInit = true;
            }
          }
        },
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: _buildVideoLoadingPreview(),
        ),
      );
    }

    return VisibilityDetector(
      key: Key(_videoId),
      onVisibilityChanged: (info) {
        if (!mounted || _disposed || _controller == null || _isTransferred) {
          return;
        }

        _visibleFraction = info.visibleFraction;

        if (_visibleFraction < 0.05) {
          _VisibleVideoCoordinator.remove(_videoId);
          _safePause();
          return;
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              _disposed ||
              _controller == null ||
              !_initialized ||
              _isTransferred) {
            return;
          }

          _VisibleVideoCoordinator.update(_videoId, _visibleFraction);
          _syncPlaybackWithVisibility();
        });
      },
      child: GestureDetector(
        onTap: () {
          final activeCtrl = _controller;
          if (activeCtrl == null || !activeCtrl.value.isInitialized) return;

          _safeSetState(() => _isTransferred = true);

          _VisibleVideoCoordinator.clearActive();
          _VisibleVideoCoordinator.remove(_videoId);

          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (_, animation, __) => FadeTransition(
                opacity: animation,
                child: _PostDetailPage(
                  post: widget.post,
                  isDark: widget.isDark,
                  existingController: activeCtrl,
                  isSupervisor: _isCurrentUserSupervisor(),
                ),
              ),
              transitionDuration: const Duration(milliseconds: 300),
            ),
          ).then((_) {
            if (!mounted || _disposed) return;

            _safeSetState(() => _isTransferred = false);

            _VisibleVideoCoordinator.update(_videoId, _visibleFraction);
            _syncPlaybackWithVisibility();
          });
        },
        behavior: HitTestBehavior.opaque,
        child: AspectRatio(
          aspectRatio: (() {
            try {
              final ratio = ctrl.value.aspectRatio;
              return ratio.isFinite && ratio > 0 ? ratio : 16 / 9;
            } catch (_) {
              return 16 / 9;
            }
          })(),
          child: Stack(
            children: [
              Positioned.fill(child: VideoPlayer(ctrl)),

              if (_showLoadingOverlay)
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: _showLoadingOverlay ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: _buildVideoLoadingPreview(),
                  ),
                ),

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
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _GlobalVideoMute.muted,
                          builder: (_, muted, __) {
                            return Icon(
                              muted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              color: const Color.fromARGB(199, 255, 255, 255),
                              size: 16,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        final ctrl = _controller;
                        if (ctrl == null || !ctrl.value.isInitialized) return;

                        if (ctrl.value.isPlaying) {
                          _userPaused = true;
                          _VisibleVideoCoordinator.remove(_videoId);
                          _safePause();
                          _safeSetState(() {});
                        } else {
                          _userPaused = false;
                          _VisibleVideoCoordinator.update(
                            _videoId,
                            _visibleFraction,
                          );
                          _syncPlaybackWithVisibility();
                        }
                      },
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          ctrl.value.isPlaying
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

              Positioned(
                left: 0,
                right: 0,
                bottom: -9,
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
                                    color: Color.fromARGB(255, 255, 255, 255),
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
                            trackShape: const _FullWidthRectSliderTrackShape(),
                            thumbShape: _isDraggingSlider
                                ? const RoundSliderThumbShape(enabledThumbRadius: 7)
                                : SliderComponentShape.noThumb,
                            overlayShape: _isDraggingSlider
                                ? const RoundSliderOverlayShape(overlayRadius: 14)
                                : SliderComponentShape.noOverlay,
                            activeTrackColor:
                                const Color.fromARGB(255, 255, 255, 255),
                            inactiveTrackColor: Colors.white30,
                            thumbColor:
                                const Color.fromARGB(255, 255, 255, 255),
                            overlayColor:
                                const Color.fromARGB(255, 255, 255, 255)
                                    .withOpacity(0.25),
                          ),
                          child: SizedBox(
                            height: 20,
                            child: Slider(
                              value: pos,
                              min: 0,
                              max: safeMax,
                              onChangeStart: (_) {
                                _safePause();
                                _safeSetState(() => _isDraggingSlider = true);
                              },
                              onChanged: (v) {
                                _safeSeekTo(Duration(milliseconds: v.toInt()));
                              },
                              onChangeEnd: (_) {
                                _syncPlaybackWithVisibility();
                                _safeSetState(() => _isDraggingSlider = false);
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
  return Container(
    width: double.infinity,
    height: double.infinity,
    color: Colors.white,
    alignment: Alignment.center,
    child: Image.network(
      url,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      headers: const {'Accept': 'image/*'},
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const ColoredBox(
          color: Colors.white,
          child: Center(
            child: CircularProgressIndicator(color: gold, strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: Colors.white,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.black38,
            size: 42,
          ),
        ),
      ),
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