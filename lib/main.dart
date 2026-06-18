import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'pages/publications_page.dart';
import 'pages/files_page.dart';
import 'pages/courses_page.dart';
import 'pages/settings_page.dart';
import 'widgets/shared_widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firebase_notification_service.dart';

SystemUiOverlayStyle appSystemBarsStyle(bool isDark) {
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: isDark ? const Color(0xFF050505) : const Color(0xFFF7F4EE),
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    // مهم جداً للـ iOS: الثيم الفاتح يحتاج light حتى تظهر الأيقونات/النصوص بالأسود.
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
  );
}

void applyAppSystemBarsStyle(bool isDark) {
  SystemChrome.setSystemUIOverlayStyle(appSystemBarsStyle(isDark));
}
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  if (isAndroid) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await FirebaseNotificationService.initialize();
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  applyAppSystemBarsStyle(false);

  runApp(const DrMajedApp());
}

class DrMajedApp extends StatefulWidget {
  const DrMajedApp({super.key});
  @override
  State<DrMajedApp> createState() => _DrMajedAppState();
}

class _DrMajedAppState extends State<DrMajedApp> with WidgetsBindingObserver {
  static const String _themePrefsKey = 'app_is_dark_theme';

  // الثيم الافتراضي للتطبيق هو الوضع الفاتح.
  bool _isDark = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applySystemBarsStyle(_isDark);
    _loadSavedTheme();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applySystemBarsStyle(_isDark);
    }
  }

  Future<void> _loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIsDark = prefs.getBool(_themePrefsKey) ?? false;

    if (!mounted) return;
    setState(() => _isDark = savedIsDark);
    _applySystemBarsStyle(savedIsDark);
  }

  void _toggleTheme(bool val) {
    setState(() => _isDark = val);
    _applySystemBarsStyle(val);
    unawaited(_saveThemePreference(val));
  }

  Future<void> _saveThemePreference(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themePrefsKey, val);
  }

  SystemUiOverlayStyle _systemBarsStyle(bool dark) => appSystemBarsStyle(dark);

  void _applySystemBarsStyle(bool dark) {
    applyAppSystemBarsStyle(dark);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      applyAppSystemBarsStyle(dark);
    });
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) applyAppSystemBarsStyle(_isDark);
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _systemBarsStyle(_isDark),
      child: MaterialApp(
        title: 'د. ماجد البنا',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        theme: _buildTheme(_isDark),
        home: MainScaffold(isDark: _isDark, onThemeToggle: _toggleTheme),
      ),
    );
  }

  ThemeData _buildTheme(bool dark) {
    const gold = Color(0xFFD4A017);
    const goldLight = Color(0xFFE8B84B);
    if (dark) {
      return ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050505),
        primaryColor: gold,
        colorScheme: const ColorScheme.dark(
          primary: gold,
          secondary: Color(0xFFD48D09),
          surface: Color(0xFF101010),
        ),
        appBarTheme: AppBarTheme(systemOverlayStyle: appSystemBarsStyle(true)),
        fontFamily: 'Cairo',
        useMaterial3: true,
      );
    }
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF7F4EE),
      primaryColor: gold,
      colorScheme: const ColorScheme.light(
        primary: gold,
        secondary: goldLight,
        surface: Colors.white,
      ),
      appBarTheme: AppBarTheme(systemOverlayStyle: appSystemBarsStyle(false)),
      fontFamily: 'Cairo',
      useMaterial3: true,
    );
  }
}

// ─────────────────────────────────────────────
//  MAIN SCAFFOLD
// ─────────────────────────────────────────────

class MainScaffold extends StatefulWidget {
  final bool isDark;
  final ValueChanged<bool> onThemeToggle;
  const MainScaffold({super.key, required this.isDark, required this.onThemeToggle});
  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold>
    with TickerProviderStateMixin {
  // Pages order: 0=publications, 1=files, 2=home, 3=courses, 4=settings
  // Start at index 2 (home)
  int _currentIndex = 2;
  late PageController _pageController;
  late AnimationController _navAnimCtrl;
  final AppLinks _appLinks = AppLinks();
  bool _isNavCompact = false;
  double _navScrollDelta = 0;
  bool _navAnimationTargetCompact = false;
StreamSubscription<Uri>? _deepLinkSub;
StreamSubscription<Map<String, dynamic>>? _notificationClickSub;
int? _pendingPostId;

  @override
  void initState() {
    super.initState();
    applyAppSystemBarsStyle(widget.isDark);
    _pageController = PageController(initialPage: 2, keepPage: true);
    _navAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 360),
    );

    _initDeepLinks();
    _initNotificationClicks();
  }

  @override
  void didUpdateWidget(covariant MainScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDark != widget.isDark) {
      applyAppSystemBarsStyle(widget.isDark);
    }
  }

  Future<void> _initDeepLinks() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (_) {}

    await _deepLinkSub?.cancel();
    _deepLinkSub = _appLinks.uriLinkStream.listen(
      _handleDeepLink,
      onError: (_) {},
    );
  }
void _initNotificationClicks() {
  final initialData = FirebaseNotificationService.consumeInitialNotificationData();

  if (initialData != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openFromNotificationData(initialData);
    });
  }

  _notificationClickSub =
      FirebaseNotificationService.notificationClicks.listen(_openFromNotificationData);
}

void _openFromNotificationData(Map<String, dynamic> data) {
  final rawPostId = data['post_id'] ?? data['postId'];
  final postId = int.tryParse('$rawPostId');

  if (postId != null && postId > 0) {
    _openSharedPost(postId);
    return;
  }

  _openPublicationsPageFromNotification();
}

void _openPublicationsPageFromNotification() {
  if (!mounted) return;

  if (_currentIndex == 0) {
    PublicationsPageScrollBus.goTop();
    return;
  }

  _expandNavBar();
  setState(() {
    _currentIndex = 0;
  });

  if (_pageController.hasClients) {
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }
}
  void _handleDeepLink(Uri uri) {
    int? postId;

    // روابط التطبيق المباشرة:
    // majidalbana://post/123
    // majidalbana://post?id=123
    if (uri.scheme == 'majidalbana' && uri.host == 'post') {
      if (uri.pathSegments.isNotEmpty) {
        postId = int.tryParse(uri.pathSegments.first);
      }
      postId ??= int.tryParse(uri.queryParameters['id'] ?? '');
    }

    // روابط الموقع:
    // https://majidalbana.com/post/123
    // https://majidalbana.com/post/index.php?id=123
    // https://www.majidalbana.com/post/123
    // https://www.majidalbana.com/post/index.php?id=123
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        (uri.host == 'majidalbana.com' || uri.host == 'www.majidalbana.com') &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'post') {
      if (uri.pathSegments.length >= 2) {
        final secondSegment = uri.pathSegments[1];

        if (secondSegment != 'index.php') {
          postId = int.tryParse(secondSegment);
        }
      }

      postId ??= int.tryParse(uri.queryParameters['id'] ?? '');
    }

    if (postId == null || postId <= 0) return;

    _openSharedPost(postId);
  }

  void _openSharedPost(int postId) {
    _pendingPostId = postId;

    if (!mounted) return;

    if (_currentIndex != 0) {
      _expandNavBar();
      setState(() {
        _currentIndex = 0;
      });
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 360), () {
        final id = _pendingPostId;
        if (!mounted || id == null) return;
        _pendingPostId = null;
        PublicationsPageDeepLinkBus.openPost(id);
      });
    });
  }

  @override
  void dispose() {
_deepLinkSub?.cancel();
_notificationClickSub?.cancel();
_pageController.dispose();
_navAnimCtrl.dispose();
super.dispose();
  }

  void _animateNavBar({required bool compact}) {
    if (_navAnimationTargetCompact == compact) return;
    _navAnimationTargetCompact = compact;
    _isNavCompact = compact;

    _navAnimCtrl.animateTo(
      compact ? 1.0 : 0.0,
      duration: compact
          ? const Duration(milliseconds: 420)
          : const Duration(milliseconds: 360),
      curve: compact ? Curves.easeOutCubic : Curves.easeOutQuart,
    );
  }

  void _expandNavBar() {
    _navScrollDelta = 0;
    _animateNavBar(compact: false);
  }

  bool _handleNavScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is ScrollUpdateNotification && notification.scrollDelta != null) {
      final delta = notification.scrollDelta!;

      if (delta > 0) {
        _navScrollDelta = (_navScrollDelta + delta).clamp(0.0, 120.0).toDouble();
        if (!_isNavCompact && _navScrollDelta >= 76) {
          _navScrollDelta = 0;
          _animateNavBar(compact: true);
        }
      } else if (delta < 0) {
        _navScrollDelta = (_navScrollDelta + delta).clamp(-120.0, 0.0).toDouble();
        if (_isNavCompact && _navScrollDelta <= -52) {
          _navScrollDelta = 0;
          _animateNavBar(compact: false);
        }
      }
    }

    if (notification is ScrollEndNotification || notification is UserScrollNotification) {
      _navScrollDelta = 0;
    }

    return false;
  }

  void _onTabTapped(int index) {
    // 0 = المنشورات، 1 = الملفات
    // إذا أنت داخل نفس القسم وضغطت زر القسم مرة ثانية، يصعد لأعلى الصفحة.
    if (_currentIndex == index) {
      if (_isNavCompact || _navScrollDelta != 0) {
        _expandNavBar();
      }
      if (index == 0) {
        PublicationsPageScrollBus.goTop();
      } else if (index == 1) {
        FilesPageScrollBus.goTop();
      }
      return;
    }

    _expandNavBar();
    setState(() {
      _currentIndex = index;
    });

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F0E8);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) applyAppSystemBarsStyle(isDark);
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: appSystemBarsStyle(isDark),
      child: Directionality(
      textDirection: TextDirection.rtl,
child: Scaffold(
  resizeToAvoidBottomInset: false,
  backgroundColor: bg,
  body: Stack(
          children: [
            // ── PageView for swipe navigation ──
            NotificationListener<ScrollNotification>(
              onNotification: _handleNavScrollNotification,
              child: PageView(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (index) {
                  applyAppSystemBarsStyle(isDark);
                  _expandNavBar();
                  setState(() {
                    _currentIndex = index;
                  });
                },
                children: [
                  PublicationsPage(isDark: isDark),
                  FilesPage(isDark: isDark),
                  HomePage(isDark: isDark, onOpenSection: _onTabTapped),
                  CoursesPage(isDark: isDark),
                  SettingsPage(isDark: isDark, onThemeToggle: widget.onThemeToggle),
                ],
              ),
            ),

// ── Real gradient blur box behind bottom glass nav ──
Positioned(
  left: 0,
  right: 0,
  bottom: 0,
  height: 115 + (MediaQuery.of(context).padding.bottom > 30
      ? MediaQuery.of(context).padding.bottom
      : 30),
  child: IgnorePointer(
    child: RepaintBoundary(
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const int blurSteps = 10;
            final double totalHeight = constraints.maxHeight;
            final double stepHeight = totalHeight / blurSteps;

            return Stack(
              children: List.generate(blurSteps, (index) {
                final double progress = index / (blurSteps - 1);

                // 1.0 بالأسفل، 0.0 بالأعلى
                final double strength = 1.0 - progress;

                // تدرج ناعم لكن بعدد طبقات أقل حتى لا يقطع التصفح
                final double sigma = 24.0 * strength * strength;

                if (sigma <= 0.45) {
                  return const SizedBox.shrink();
                }

                return Positioned(
                  left: 0,
                  right: 0,
                  bottom: index * stepHeight,
                  height: stepHeight + 3,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: sigma,
                        sigmaY: sigma,
                      ),
                      child: const ColoredBox(
                        color: Color(0x01000000),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    ),
  ),
),

            // ── Premium Floating Nav Bar ──
            Positioned(
              left: 16,
              right: 16,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 30),
child: AnimatedBuilder(
  animation: _navAnimCtrl,
  builder: (context, _) {
    final t = Curves.easeOutCubic.transform(_navAnimCtrl.value);
    final scale = ui.lerpDouble(1.0, 0.80, t)!;
    final translateY = ui.lerpDouble(0.0, 16.0, t)!;

    return Transform.translate(
      offset: Offset(0, translateY),
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.bottomCenter,
        filterQuality: FilterQuality.medium,
        child: _PremiumNavBar(
          currentIndex: _currentIndex,
          isDark: isDark,
          compactAmount: t,
          onTap: _onTabTapped,
        ),
      ),
    );
  },
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

// ─────────────────────────────────────────────
//  PREMIUM FLOATING NAV BAR
// ─────────────────────────────────────────────

class _PremiumNavBar extends StatelessWidget {
  final int currentIndex;
  final bool isDark;
final double compactAmount;
final ValueChanged<int> onTap;

// تحكم بالغواش
// كلما زادت القيمة يصير الخلف مغوش أكثر
static const double normalBlur = 18;
static const double compactBlur = 18;

// تحكم بتعتيم / صلابة خلفية البار
// كلما زادت القيمة يصير البار أغمق / أصلب ويقل ظهور الغواش
// كلما قلت القيمة يصير زجاجي أكثر ويبين الغواش
static const double darkNormalOpacity = 0.42;
static const double darkCompactOpacity = 0.9;

static const double lightNormalOpacity = 0.55;
static const double lightCompactOpacity = 0.9;

  const _PremiumNavBar({
    required this.currentIndex,
    required this.isDark,
    required this.compactAmount,
    required this.onTap,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
boxShadow: isDark
    ? [
        BoxShadow(
          color: const ui.Color.fromARGB(255, 0, 0, 0).withOpacity(0.2),
          blurRadius: 26,
          spreadRadius: -8,
          offset: const Offset(0, 0),
        ),
      ]
    : [
        BoxShadow(
          color: Colors.black.withOpacity(0.28),
          blurRadius: 18,
          spreadRadius: -3,
          offset: const Offset(0, 0),
        ),
      ],
      ),
child: ClipRRect(
  borderRadius: BorderRadius.circular(40),
  clipBehavior: Clip.antiAlias,
  child: BackdropFilter(
filter: ui.ImageFilter.blur(
  sigmaX: ui.lerpDouble(normalBlur, compactBlur, compactAmount)!,
  sigmaY: ui.lerpDouble(normalBlur, compactBlur, compactAmount)!,
),
    child: Container(
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
color: isDark
    ? const ui.Color(0xFF101010).withOpacity(
        ui.lerpDouble(darkNormalOpacity, darkCompactOpacity, compactAmount)!,
      )
    : Colors.white.withOpacity(
        ui.lerpDouble(lightNormalOpacity, lightCompactOpacity, compactAmount)!,
      ),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(
                  ui.lerpDouble(0.14, 0.20, compactAmount)!,
                )
              : Colors.white.withOpacity(
                  ui.lerpDouble(0.65, 0.50, compactAmount)!,
                ),
          width: 1.5,
        ),
        boxShadow: const [],
      ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.photo_library_outlined,
                activeIcon: Icons.photo_library_rounded,
                label: 'المنشورات',
                index: 0,
                current: currentIndex,
                isDark: isDark,
                onTap: onTap,
              ),
              _NavItem(
                icon: Icons.folder_outlined,
                activeIcon: Icons.folder_rounded,
                label: 'الملفات',
                index: 1,
                current: currentIndex,
                isDark: isDark,
                onTap: onTap,
              ),
              _CenterLogoButton(
                isDark: isDark,
                isActive: currentIndex == 2,
                onTap: () => onTap(2),
              ),
              _NavItem(
                icon: Icons.school_outlined,
                activeIcon: Icons.school_rounded,
                label: 'الدورات',
                index: 3,
                current: currentIndex,
                isDark: isDark,
                onTap: onTap,
              ),
              _NavItem(
                icon: Icons.tune_outlined,
                activeIcon: Icons.tune_rounded,
                label: 'الإعدادات',
                index: 4,
                current: currentIndex,
                isDark: isDark,
                onTap: onTap,
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  final int current;
  final bool isDark;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
    required this.current,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.85)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final isActive = widget.current == widget.index;
    final inactiveColor = widget.isDark ? Colors.white38 : Colors.black38;

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap(widget.index);
      },
      onTapCancel: () => _ctrl.reverse(),
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: SizedBox(
          width: 58,
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                width: isActive ? 42 : 34,
                height: isActive ? 32 : 26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isActive
                      ? gold.withOpacity(widget.isDark ? 0.18 : 0.14)
                      : Colors.transparent,
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: child,
                    ),
                    child: Icon(
                      isActive ? widget.activeIcon : widget.icon,
                      key: ValueKey(isActive),
                      color: isActive ? gold : inactiveColor,
                      size: isActive ? 28 : 26,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: isActive ? gold : inactiveColor,
                  fontSize: isActive ? 8.5 : 7.5,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  fontFamily: 'Cairo',
                ),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterLogoButton extends StatefulWidget {
  final bool isDark;
  final bool isActive;
  final VoidCallback onTap;

  const _CenterLogoButton({
    required this.isDark,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_CenterLogoButton> createState() => _CenterLogoButtonState();
}

class _CenterLogoButtonState extends State<_CenterLogoButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _pressAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _pressAnim = Tween<double>(begin: 1.0, end: 0.85)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final inactiveColor = widget.isDark ? const ui.Color.fromARGB(135, 255, 255, 255) : Colors.black38;

    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _pressAnim,
        child: SizedBox(
          width: 58,
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                width: widget.isActive ? 46 : 44,
                height: widget.isActive ? 46: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(25),
                  color: widget.isActive
                      ? const ui.Color(0xFFD4A017).withOpacity(widget.isDark ? 0 : 0.14)
                      : const ui.Color.fromARGB(0, 0, 0, 0),
                ),
                child: Center(
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                    width: widget.isActive ? 50 : 50,
                    height: widget.isActive ? 50 : 50,
                    color: widget.isActive ? gold : inactiveColor,
                    colorBlendMode: BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(height: 0),

            ],
          ),
        ),
      ),
    );
  }
}
// ─────────────────────────────────────────────
//  SHARED WIDGETS
// ─────────────────────────────────────────────



enum _LatestUpdateType { publication, file, lecture }

class _LatestHomeUpdate {
  final _LatestUpdateType type;
  final int sectionIndex;
  final int itemId;
  final IconData icon;
  final String title;
  final String headline;
  final String subtitle;
  final String imageUrl;
  final String targetUrl;
  final Color accent;

  const _LatestHomeUpdate({
    required this.type,
    required this.sectionIndex,
    required this.itemId,
    required this.icon,
    required String? title,
    required String? headline,
    required String? subtitle,
    required String? imageUrl,
    required String? targetUrl,
    required this.accent,
  })  : title = title ?? '',
        headline = headline ?? '',
        subtitle = subtitle ?? '',
        imageUrl = imageUrl ?? '',
        targetUrl = targetUrl ?? '';

  String get signature =>
      '${type.name}|$itemId|$headline|$subtitle|$imageUrl|$targetUrl';

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'sectionIndex': sectionIndex,
        'itemId': itemId,
        'title': title,
        'headline': headline,
        'subtitle': subtitle,
        'imageUrl': imageUrl,
        'targetUrl': targetUrl,
      };

  static _LatestHomeUpdate? fromJson(Map<String, dynamic> json) {
    final typeName = '${json['type'] ?? ''}';
    _LatestUpdateType? type;
    for (final value in _LatestUpdateType.values) {
      if (value.name == typeName) {
        type = value;
        break;
      }
    }
    if (type == null) return null;

    return _LatestHomeUpdate(
      type: type,
      sectionIndex: int.tryParse('${json['sectionIndex'] ?? _sectionIndexFor(type)}') ??
          _sectionIndexFor(type),
      itemId: int.tryParse('${json['itemId'] ?? 0}') ?? 0,
      icon: _iconFor(type),
      title: '${json['title'] ?? _titleFor(type)}',
      headline: '${json['headline'] ?? ''}',
      subtitle: '${json['subtitle'] ?? ''}',
      imageUrl: '${json['imageUrl'] ?? ''}',
      targetUrl: '${json['targetUrl'] ?? ''}',
      accent: _accentFor(type),
    );
  }

  static int _sectionIndexFor(_LatestUpdateType type) {
    switch (type) {
      case _LatestUpdateType.publication:
        return 0;
      case _LatestUpdateType.file:
        return 1;
      case _LatestUpdateType.lecture:
        return 3;
    }
  }

  static IconData _iconFor(_LatestUpdateType type) {
    switch (type) {
      case _LatestUpdateType.publication:
        return Icons.photo_library_rounded;
      case _LatestUpdateType.file:
        return Icons.picture_as_pdf_rounded;
      case _LatestUpdateType.lecture:
        return Icons.school_rounded;
    }
  }

  static Color _accentFor(_LatestUpdateType type) {
    switch (type) {
      case _LatestUpdateType.publication:
        return const Color(0xFFD4A017);
      case _LatestUpdateType.file:
        return const ui.Color.fromARGB(255, 232, 75, 75);
      case _LatestUpdateType.lecture:
        return const Color(0xFF43A047);
    }
  }

  static String _titleFor(_LatestUpdateType type) {
    switch (type) {
      case _LatestUpdateType.publication:
        return 'آخر منشور';
      case _LatestUpdateType.file:
        return 'آخر ملف';
      case _LatestUpdateType.lecture:
        return 'آخر محاضرة';
    }
  }
}

class _LatestUpdateTile extends StatefulWidget {
  final _LatestHomeUpdate update;
  final bool isDark;
  final Color innerBg;
  final Color textPrimary;
  final Color textSub;
  final VoidCallback onTap;

  const _LatestUpdateTile({
    required this.update,
    required this.isDark,
    required this.innerBg,
    required this.textPrimary,
    required this.textSub,
    required this.onTap,
  });

  @override
  State<_LatestUpdateTile> createState() => _LatestUpdateTileState();
}

class _LatestUpdateTileState extends State<_LatestUpdateTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final update = widget.update;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        scale: _pressed ? 0.985 : 1,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.innerBg.withOpacity(widget.isDark ? 0.78 : 0.92),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _pressed ? update.accent.withOpacity(0.45) : update.accent.withOpacity(0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: update.accent.withOpacity(_pressed ? 0.14 : 0.07),
                blurRadius: _pressed ? 18 : 12,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              _LatestUpdateIcon(update: update, isDark: widget.isDark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          update.title,
                          style: TextStyle(
                            color: update.accent,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: update.accent.withOpacity(0.65),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'اضغط للانتقال',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.textSub.withOpacity(0.2),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      update.headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        height: 1.35,
                      ),
                    ),
                    if (update.subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        update.subtitle.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.textSub,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_back_ios_new_rounded, color: update.accent, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _LatestUpdateIcon extends StatelessWidget {
  final _LatestHomeUpdate update;
  final bool isDark;

  const _LatestUpdateIcon({
    required this.update,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final hasNetworkImage = update.imageUrl.trim().isNotEmpty;
    final isLecture = update.type == _LatestUpdateType.lecture;

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: update.accent.withOpacity(0.30)),
        boxShadow: [
          BoxShadow(
            color: update.accent.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isLecture)
              Image.asset(
                'assets/images/map.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackBackground(),
              )
            else if (hasNetworkImage)
              Image.network(
                update.imageUrl,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => _fallbackBackground(),
              )
            else
              _fallbackBackground(),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Colors.black.withOpacity(isDark ? 0.46 : 0.34),
                    update.accent.withOpacity(isDark ? 0.34 : 0.28),
                  ],
                ),
              ),
            ),
            Center(
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.7),
                ),
                child: Icon(update.icon, color: update.accent, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackBackground() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            update.accent.withOpacity(0.25),
            update.accent.withOpacity(0.08),
          ],
        ),
      ),
    );
  }
}

class _GoldDivider extends StatelessWidget {
  const _GoldDivider();
  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, Color(0xFFD4A017), Colors.transparent],
          ),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final bool isDark;
  const _SectionTitle(this.text, {required this.isDark});
  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFFD4A017),
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      );
}

class _HeroWatermarkPattern extends StatelessWidget {
  final bool isDark;
  const _HeroWatermarkPattern({required this.isDark});

  static const double _scale = 0.66;
  static const double _offsetX = 0.0;
  static const double _speed = 30.0;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: isDark ? 0.4 : 0.7,
        child: _TiledImagePainter(
          assetPath: 'assets/images/bg.png',
          scale: _scale,
          offsetX: _offsetX,
          speed: _speed,
          color: isDark ? Colors.white : const Color(0xFF8A5E00),
        ),
      ),
    );
  }
}

class _TiledImagePainter extends StatefulWidget {
  final String assetPath;
  final double scale;
  final double offsetX;
  final double speed;
  final Color color;

  const _TiledImagePainter({
    required this.assetPath,
    required this.scale,
    required this.offsetX,
    required this.speed,
    required this.color,
  });

  @override
  State<_TiledImagePainter> createState() => _TiledImagePainterState();
}

class _TiledImagePainterState extends State<_TiledImagePainter>
    with SingleTickerProviderStateMixin {
  ui.Image? _image;
  late Ticker _ticker;
  double _offsetY = 0.0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1000000.0;
      _last = elapsed;
      if (mounted) setState(() => _offsetY -= widget.speed * dt);
    })
      ..start();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final data = await rootBundle.load(widget.assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _image = frame.image);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) return const SizedBox.expand();
    return CustomPaint(
      painter: _WatermarkPainter(
        image: _image!,
        scale: widget.scale,
        offsetX: widget.offsetX,
        offsetY: _offsetY,
        color: widget.color,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  final ui.Image image;
  final double scale;
  final double offsetX;
  final double offsetY;
  final Color color;

  _WatermarkPainter({
    required this.image,
    required this.scale,
    required this.offsetX,
    required this.offsetY,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn);
    final tileW = image.width * scale;
    final tileH = image.height * scale;
    final startX = (offsetX % tileW) - tileW;
    final startY = offsetY % tileH;
    for (double y = startY - tileH * 2; y < size.height + tileH; y += tileH) {
      for (double x = startX - tileW; x < size.width + tileW; x += tileW) {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(x, y, tileW, tileH),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WatermarkPainter old) => true;
}

// ─────────────────────────────────────────────
//  PREMIUM APP BAR
// ─────────────────────────────────────────────

class _PremiumAppBar extends StatelessWidget {
  final String title;
  final bool isDark;
  const _PremiumAppBar({required this.title, required this.isDark});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      toolbarHeight: 68,
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
      title: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFE8B84B), Color(0xFF8A5E00)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: gold.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                  color: Colors.white,
                  colorBlendMode: BlendMode.srcIn,
                ),
              ),
            ),
            Text(
              title,
              style: const TextStyle(
                color: gold,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  GOLD BUTTON
// ─────────────────────────────────────────────

class _GoldButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _GoldButton({required this.label, required this.icon, required this.onTap});
  @override
  State<_GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<_GoldButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.94)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              gradient: const LinearGradient(
                colors: [Color(0xFFEEC04F), Color(0xFFD4A017), Color(0xFFAD7A00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD4A017).withOpacity(0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────
//  QUICK CARD
// ─────────────────────────────────────────────

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  const _QuickCard({required this.icon, required this.label, required this.isDark});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const ui.Color.fromARGB(0, 0, 0, 0) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1000);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: gold.withOpacity(0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.25 : 0.07),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
            if (isDark)
              BoxShadow(
                color: gold.withOpacity(0.04),
                blurRadius: 12,
              ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: gold.withOpacity(0.12),
              ),
              child: Icon(icon, color: gold, size: 28),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                  color: textColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  STAT CARD
// ─────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final bool isDark;
  const _StatCard({required this.value, required this.label, required this.isDark});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF181818) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1000);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: gold.withOpacity(0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    color: gold, fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(color: textColor, fontSize: 11, height: 1.4),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  TAG
// ─────────────────────────────────────────────

class _Tag extends StatelessWidget {
  final String label;
  final IconData icon;
  const _Tag({required this.label, required this.icon});
  static const gold = Color(0xFFD4A017);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: gold.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: gold),
            const SizedBox(width: 3),
            Text(label,
                style: const TextStyle(
                    color: gold, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────
//  SETTINGS CARD
// ─────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  const _SettingsCard({required this.child, required this.isDark});
  static const gold = Color(0xFFD4A017);
  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF181818) : Colors.white;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gold.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────
//  HOME PAGE
// ─────────────────────────────────────────────

class HomePage extends StatefulWidget {
  final bool isDark;
  final ValueChanged<int> onOpenSection;
  const HomePage({super.key, required this.isDark, required this.onOpenSection});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {

  static const String _latestPostsApi =
      'https://majidalbana.com/admin/posts/load_posts.php';
  static const String _latestFilesApi =
      'https://majidalbana.com/admin/pdf-posts/load_pdf_posts.php';
  static const String _latestCoursesApi =
      'https://majidalbana.com/admin/table/load_schedule.php';
  static const String _latestHomeCacheKey = 'latest_home_updates_cache_v2';
  static const String _postImageBaseUrl = 'https://majidalbana.com/uploads/';
  static const String _fileThumbBaseUrl = 'https://majidalbana.com/uploads-pdf/img/';

  Timer? _latestUpdatesTimer;
  bool _loadingLatestUpdates = true;
  List<_LatestHomeUpdate> _latestUpdates = [];

  late AnimationController _ctrl;
  late Animation<double> _heroFade;
  late Animation<Offset> _heroSlide;
  Widget _buildInfoTile({
  required IconData icon,
  required String title,
  required String value,
  required Color color,
  required bool isDark,
}) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF1A1000),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildSocialTile({
  required IconData icon,
  required String label,
  required Color color,
  required bool isDark,
}) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}
Widget _buildStat(String value, String label, bool isDark) {
  return Expanded(
    child: Column(
      children: [
        Text(value, style: const TextStyle(color: gold, fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 10), textAlign: TextAlign.center),
      ],
    ),
  );
}
Widget _buildContactRow({
  required IconData icon,
  required String title,
  required List<String> lines,
  required bool isDark,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: gold.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: gold.withOpacity(0.25)),
          ),
          child: Icon(icon, color: gold, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: gold,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              ...lines.map((line) => Text(
                line,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 13,
                  height: 1.7,
                ),
              )),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildContactDivider() => Container(
  height: 1,
  color: gold.withOpacity(0.08),
  margin: const EdgeInsets.symmetric(horizontal: 4),
);

Widget _buildSocialBtn(IconData icon, Color color) {
  return Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Icon(icon, color: color, size: 22),
  );
}

  Future<void> _loadLatestHomeUpdates({bool silent = false}) async {
    if (!mounted) return;

    if (!silent && _latestUpdates.isEmpty) {
      final cached = await _loadCachedLatestHomeUpdates();
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _latestUpdates = cached;
          _loadingLatestUpdates = false;
        });
      }
    }

    if (!silent && _latestUpdates.isEmpty && mounted) {
      setState(() => _loadingLatestUpdates = true);
    }

    try {
      final results = await Future.wait<_LatestHomeUpdate?>([
        _fetchLatestPublication(),
        _fetchLatestFile(),
        _fetchLatestLecture(),
      ]);

      if (!mounted) return;

      final freshUpdates = results.whereType<_LatestHomeUpdate>().toList();
      await _saveLatestHomeUpdatesToCache(freshUpdates);

      final oldSignature = _latestUpdates.map((e) => e.signature).join(':::');
      final newSignature = freshUpdates.map((e) => e.signature).join(':::');

      if (oldSignature != newSignature || _loadingLatestUpdates) {
        setState(() {
          _latestUpdates = freshUpdates;
          _loadingLatestUpdates = false;
        });
      } else if (_loadingLatestUpdates) {
        setState(() => _loadingLatestUpdates = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingLatestUpdates = false);
    }
  }

  Future<List<_LatestHomeUpdate>> _loadCachedLatestHomeUpdates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_latestHomeCacheKey);
      if (raw == null || raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => _LatestHomeUpdate.fromJson(Map<String, dynamic>.from(e)))
          .whereType<_LatestHomeUpdate>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveLatestHomeUpdatesToCache(List<_LatestHomeUpdate> updates) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _latestHomeCacheKey,
        jsonEncode(updates.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<_LatestHomeUpdate?> _fetchLatestPublication() async {
    final response = await http
        .get(Uri.parse(_latestPostsApi))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List || decoded.isEmpty) return null;

    final items = decoded.whereType<Map>().toList()
      ..sort((a, b) {
        final ad = DateTime.tryParse('${a['created_at'] ?? ''}') ?? DateTime(1970);
        final bd = DateTime.tryParse('${b['created_at'] ?? ''}') ?? DateTime(1970);
        return bd.compareTo(ad);
      });

    final item = Map<String, dynamic>.from(items.first);
    final text = _cleanLatestText(item['content']);

    return _LatestHomeUpdate(
      type: _LatestUpdateType.publication,
      sectionIndex: 0,
      itemId: int.tryParse('${item['id'] ?? 0}') ?? 0,
      icon: Icons.photo_library_rounded,
      title: 'آخر منشور',
      headline: text.isEmpty ? 'منشور جديد من د.ماجد البنا' : text,
      subtitle: _formatLatestDate('${item['created_at'] ?? ''}'),
      imageUrl: _resolveLatestImageUrl(item['image'], _postImageBaseUrl),
      targetUrl: '',
      accent: const Color(0xFFD4A017),
    );
  }

  Future<_LatestHomeUpdate?> _fetchLatestFile() async {
    final uri = Uri.parse(_latestFilesApi);
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List || decoded.isEmpty) return null;

    final items = decoded.whereType<Map>().toList()
      ..sort((a, b) {
        final ad = DateTime.tryParse('${a['created_at'] ?? ''}') ?? DateTime(1970);
        final bd = DateTime.tryParse('${b['created_at'] ?? ''}') ?? DateTime(1970);
        return bd.compareTo(ad);
      });

    final item = Map<String, dynamic>.from(items.first);
    final title = _cleanLatestText(item['title']);
    final category = _cleanLatestText(item['category']);
    final date = _formatLatestDate('${item['created_at'] ?? ''}');

    return _LatestHomeUpdate(
      type: _LatestUpdateType.file,
      sectionIndex: 1,
      itemId: int.tryParse('${item['id'] ?? 0}') ?? 0,
      icon: Icons.picture_as_pdf_rounded,
      title: 'آخر ملف',
      headline: title.isEmpty ? 'ملف جديد متاح للعرض' : title,
      subtitle: category.isEmpty ? date : '$category  •  $date',
      imageUrl: _resolveLatestImageUrl(item['thumbnail'], _fileThumbBaseUrl),
      targetUrl: '',
      accent: const Color(0xFFE8B84B),
    );
  }

  Future<_LatestHomeUpdate?> _fetchLatestLecture() async {
    final response = await http
        .get(Uri.parse(_latestCoursesApi))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;

    final html = utf8.decode(response.bodyBytes);
    final rows = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true, caseSensitive: false)
        .allMatches(html)
        .map((m) => m.group(1) ?? '')
        .toList();

    for (final rowHtml in rows) {
      final cells = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true, caseSensitive: false)
          .allMatches(rowHtml)
          .map((m) => _cleanHtmlLatest(m.group(1) ?? ''))
          .toList();
      if (cells.length < 4) continue;

      final lectureNumber = cells[0];
      final day = cells[1];
      final time = cells[2];
      final location = cells[3];
      final urlMatch = RegExp(r'''href=["']([^"']+)["']''', caseSensitive: false)
          .firstMatch(rowHtml);
      final idMatch =
          RegExp(r'''data-id=["']?(\d+)["']?''', caseSensitive: false)
              .firstMatch(rowHtml);

      return _LatestHomeUpdate(
        type: _LatestUpdateType.lecture,
        sectionIndex: 3,
        itemId: int.tryParse(idMatch?.group(1) ?? '0') ?? 0,
        icon: Icons.school_rounded,
        title: 'آخر محاضرة',
        headline: lectureNumber.isEmpty ? 'محاضرة جديدة' : 'محاضرة $lectureNumber',
        subtitle: [day, time, location].where((e) => e.trim().isNotEmpty).join('  •  '),
        imageUrl: '',
        targetUrl: urlMatch?.group(1)?.trim() ?? '',
        accent: const Color(0xFF43A047),
      );
    }

    return null;
  }

  String _cleanLatestText(dynamic value) {
    return '${value ?? ''}'
        .replaceAll(RegExp(r'<[^>]*>', dotAll: true), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _cleanHtmlLatest(String value) => _cleanLatestText(value);

  String _formatLatestDate(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return 'تحديث جديد';
    final dateOnly = raw.split(' ').first;
    return dateOnly.isEmpty ? 'تحديث جديد' : dateOnly;
  }

  String _resolveLatestImageUrl(dynamic value, String baseUrl) {
    final raw = '${value ?? ''}'.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return '$baseUrl$raw';
  }

  Future<void> _openLatestUpdate(_LatestHomeUpdate update) async {
    HapticFeedback.selectionClick();

    if (update.type == _LatestUpdateType.lecture) {
      final rawUrl = update.targetUrl.trim();
      final uri = Uri.tryParse(rawUrl);
      if (uri != null && rawUrl.isNotEmpty) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    if (update.itemId <= 0 || !mounted) return;

    Widget page;
    switch (update.type) {
      case _LatestUpdateType.publication:
        page = PublicationDirectPage(
          postId: update.itemId,
          isDark: widget.isDark,
        );
        break;
      case _LatestUpdateType.file:
        page = FileDirectPage(
          fileId: update.itemId,
          isDark: widget.isDark,
        );
        break;
      case _LatestUpdateType.lecture:
        return;
    }

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
            child: page,
          );
        },
      ),
    );
  }

  Widget _buildLatestUpdatesCard({
    required bool isDark,
    required Color cardBg,
    required Color textPrimary,
    required Color textSub,
  }) {
    final borderColor = gold.withOpacity(isDark ? 0.22 : 0.18);
    final innerBg = isDark ? const Color(0xFF101010) : const Color(0xFFFFFBF2);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: isDark
              ? [const Color(0xFF191409), const Color(0xFF0E0E0E)]
              : [const Color(0xFFFFF6DF), Colors.white],
        ),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: gold.withOpacity(isDark ? 0.13 : 0.10),
            blurRadius: 28,
            spreadRadius: -8,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.32 : 0.07),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned(
              top: -42,
              left: -30,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: gold.withOpacity(0.10),
                ),
              ),
            ),
            Positioned(
              bottom: -54,
              right: -36,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(isDark ? 0.035 : 0.42),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEEC04F), Color(0xFFAD7A00)],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: gold.withOpacity(0.32),
                              blurRadius: 16,
                              offset: const Offset(0, 7),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'آخر التحديثات',
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'منشور، ملف، ومحاضرة في مكان واحد',
                              style: TextStyle(
                                color: textSub,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: gold.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: gold.withOpacity(0.24)),
                        ),
                        child: const Text(
                          'جديد',
                          style: TextStyle(color: gold, fontSize: 11, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_loadingLatestUpdates && _latestUpdates.isEmpty)
                    _buildLatestSkeleton(isDark: isDark)
                  else if (_latestUpdates.isEmpty)
                    _buildLatestEmptyState(isDark: isDark, textSub: textSub)
                  else
                    Column(
                      children: [
                        for (int i = 0; i < _latestUpdates.length; i++) ...[
                          _LatestUpdateTile(
                            update: _latestUpdates[i],
                            isDark: isDark,
                            innerBg: innerBg,
                            textPrimary: textPrimary,
                            textSub: textSub,
                            onTap: () => _openLatestUpdate(_latestUpdates[i]),
                          ),
                          if (i != _latestUpdates.length - 1) const SizedBox(height: 10),
                        ],
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

  Widget _buildLatestSkeleton({required bool isDark}) {
    return Column(
      children: List.generate(3, (index) {
        return Padding(
          padding: EdgeInsets.only(bottom: index == 2 ? 0 : 10),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.055) : Colors.black.withOpacity(0.045),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: gold.withOpacity(0.08)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: gold.withOpacity(0.14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 9, width: 100, color: gold.withOpacity(0.12)),
                      const SizedBox(height: 8),
                      Container(height: 8, width: 180, color: gold.withOpacity(0.08)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildLatestEmptyState({required bool isDark, required Color textSub}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.035),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gold.withOpacity(0.10)),
      ),
      child: Text(
        'لم يتم العثور على تحديثات حالياً',
        textAlign: TextAlign.center,
        style: TextStyle(color: textSub, fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }



  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _heroFade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _heroSlide = Tween<Offset>(
            begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
    _loadLatestHomeUpdates();
    _latestUpdatesTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _loadLatestHomeUpdates(silent: true),
    );
  }

  @override
  void dispose() {
    _latestUpdatesTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  static const gold = Color(0xFFD4A017);
  static const goldLight = Color(0xFFE8B84B);

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white70 : Colors.black54;
    final bg = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F0E8);
    final cardBg = isDark ? const Color(0xFF181818) : Colors.white;
    final heroBg = isDark ? const Color(0xFF0E0E0E) : const Color(0xFFFAF4E8);

return CustomScrollView(
  keyboardDismissBehavior:
      ScrollViewKeyboardDismissBehavior.onDrag,
  physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Premium Home App Bar ──
        SliverAppBar(
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
          title: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: [
Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Image.asset(
      'assets/images/logo.png',
      width: 36,
      height: 36,
      fit: BoxFit.contain,
      color: gold,
      colorBlendMode: BlendMode.srcIn,
    ),
    Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: Colors.white.withOpacity(0.25),
    ),
    Text(
      'الدكتور ماجد البنا',
      style: const TextStyle(
        color: gold,
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    ),
  ],
),
  _UserAvatarButton(isDark: isDark),
],
            ),
          ),
        ),

        // ── Hero Section ──
        SliverToBoxAdapter(
          child: FadeTransition(
            opacity: _heroFade,
            child: SlideTransition(
              position: _heroSlide,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const heroHeight = 340.0;
                  return SizedBox(
                    width: constraints.maxWidth,
                    height: heroHeight,
                    child: ClipRect(
                      child: Stack(
  alignment: Alignment.topCenter,
  children: [
    SizedBox(
      width: constraints.maxWidth,
      height: heroHeight,
      child: _HeroWatermarkPattern(isDark: isDark),
    ),
                          Container(
                            width: constraints.maxWidth,
                            height: heroHeight,
                            decoration: BoxDecoration(
                              color: heroBg.withOpacity(0.88),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 44),
                            child: Column(
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    // Badge
   Text(
                                  'المصمم الإنشائي',
                                  style: TextStyle(
                                    color: textSub,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    height: 1.3,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                ShaderMask(
                                  shaderCallback: (bounds) =>
                                      const LinearGradient(
                                    colors: [
                                      Color(0xFFEEC04F),
                                      Color(0xFFD4A017),
                                      Color(0xFFAD7A00),
                                    ],
                                  ).createShader(bounds),
                                  child: const Text(
                                    'د. ماجد البنا',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 38,
                                      fontWeight: FontWeight.w900,
                                      height: 1.2,
                                      letterSpacing: 0.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'الريادة في الهندسة المدنية والاستشارات الهندسية',
                                  style: TextStyle(
                                    color: textSub,
                                    fontSize: 13.5,
                                    height: 1.6,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 28),
                                _GoldButton(
                                  label: 'تواصل معنا الآن',
                                  icon: Icons.phone_rounded,
                                  onTap: () {},
                                ),
                                const SizedBox(height: 18),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: gold.withOpacity(0.12),
                                    border: Border.all(color: gold.withOpacity(0.3), width: 1),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(shape: BoxShape.circle, color: gold),
                                      ),
                                      const SizedBox(width: 6),
                                      Text('مكتب لمسات الهندسي', style: TextStyle(color: gold, fontSize: 12, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // ── Quick Access Cards ──
        SliverToBoxAdapter(
          child: Container(
            color: bg,
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Row(
              children: [
                _QuickCard(
                    icon: Icons.photo_library_outlined,
                    label: 'المنشورات',
                    isDark: isDark),
                const SizedBox(width: 10),
                _QuickCard(
                    icon: Icons.architecture_outlined,
                    label: 'المخططات الإنشائية',
                    isDark: isDark),
                const SizedBox(width: 10),
                _QuickCard(
                    icon: Icons.school_outlined,
                    label: 'الدورات',
                    isDark: isDark),
              ],
            ),
          ),
        ),

        // ── Bio Section ──
        SliverToBoxAdapter(
          child: Container(
            color: bg,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildLatestUpdatesCard(
                  isDark: isDark,
                  cardBg: cardBg,
                  textPrimary: textPrimary,
                  textSub: textSub,
                ),
                const SizedBox(height: 22),
                const _GoldDivider(),
                const SizedBox(height: 16),
                _SectionTitle('الدكتور ماجد البنا', isDark: isDark),
                const SizedBox(height: 18),
               Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.15)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // صورة الدكتور مع تدرج
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                        child: Stack(
                          children: [
                            Image.asset(
                              'assets/images/majid.png',
                              width: double.infinity,
                              height: 260,
                              fit: BoxFit.cover,
                            ),
                            // تدرج من الأسفل
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 120,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      cardBg,
                                      cardBg.withOpacity(0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // بادج الموثّق
                            Positioned(
                              top: 14,
                              left: 14,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.55),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: gold.withOpacity(0.4)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.verified_rounded, color: gold, size: 13),
                                    SizedBox(width: 4),
                                    Text('موثّق', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // المعلومات
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'د. ماجد البنا',
                                        style: TextStyle(
                                          color: isDark ? Colors.white : const Color(0xFF1A1000),
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'مصمم إنشائي استشاري',
                                        style: TextStyle(color: gold, fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: gold.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: gold.withOpacity(0.3)),
                                  ),
                                  child: Text(
                                    'دكتوراه',
                                    style: TextStyle(color: gold, fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Container(height: 1, color: gold.withOpacity(0.12)),
                            const SizedBox(height: 14),
                            Text(
                              'حاصل على دكتوراه في الهندسة المدنية، استشاري ومصمم متخصص في مجال الهندسة المدنية مع خبرة واسعة تمتد لسنوات عديدة في تصميم وتنفيذ المشاريع الهندسية المتنوعة.',
                              style: TextStyle(
                                color: textSub,
                                fontSize: 13.5,
                                height: 1.8,
                              ),
                              textAlign: TextAlign.justify,
                            ),
                            const SizedBox(height: 16),
                            // إحصائيات سريعة
                            Row(
                              children: [
                                _buildStat('25+', 'سنوات خبرة', isDark),
                                Container(width: 1, height: 36, color: gold.withOpacity(0.2), margin: const EdgeInsets.symmetric(horizontal: 12)),
                                _buildStat('٥٠٠+', 'مشروع', isDark),
                                Container(width: 1, height: 36, color: gold.withOpacity(0.2), margin: const EdgeInsets.symmetric(horizontal: 12)),
                                _buildStat('١٠٠%', 'رضا العملاء', isDark),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 18),
const SizedBox(height: 20),
         const SizedBox(height: 20),
                // ── كرت التواصل الاحترافي ──
                Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: gold.withOpacity(0.15)),
                    boxShadow: [
                      BoxShadow(
                        color: gold.withOpacity(isDark ? 0.08 : 0.06),
                        blurRadius: 30,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.35 : 0.07),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // ── هيدر مع خط ذهبي متوهج ──
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                        child: Stack(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF111111) : const Color(0xFFFFF8E7),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFEEC04F), Color(0xFFAD7A00)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: gold.withOpacity(0.4),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(Icons.contact_phone_rounded, color: Colors.white, size: 22),
                                  ),
                                  const SizedBox(width: 14),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'تواصل معنا',
                                        style: TextStyle(
                                          color: isDark ? Colors.white : const Color(0xFF1A1000),
                                          fontSize: 17,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'نحن هنا لخدمتك',
                                        style: TextStyle(color: gold, fontSize: 12, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // خط ذهبي سفلي متوهج
                            Positioned(
                              bottom: 0, left: 0, right: 0,
                              child: Container(
                                height: 1.5,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.transparent, Color(0xFFD4A017), Color(0xFFEEC04F), Color(0xFFD4A017), Colors.transparent],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── بطاقات المعلومات ──
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // شبكة 2x2 للمعلومات
                            Row(
                              children: [
                                _buildInfoTile(
                                  icon: Icons.location_on_rounded,
                                  title: 'العنوان',
                                  value: 'زيونة - بغداد',
                                  color: const Color(0xFFE53935),
                                  isDark: isDark,
                                ),
                                const SizedBox(width: 10),
                                _buildInfoTile(
                                  icon: Icons.access_time_rounded,
                                  title: 'الدوام',
                                  value: 'أحد - خميس\n٨ص - ٦م',
                                  color: const Color(0xFF43A047),
                                  isDark: isDark,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _buildInfoTile(
                                  icon: Icons.phone_rounded,
                                  title: 'الهاتف',
                                  value: '+964 770 272 4811',
                                  color: const Color(0xFF1E88E5),
                                  isDark: isDark,
                                ),
                                const SizedBox(width: 10),
                                _buildInfoTile(
                                  icon: Icons.email_rounded,
                                  title: 'البريد',
                                  value: 'info@majidalbana\n.com',
                                  color: const Color(0xFF8E24AA),
                                  isDark: isDark,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // ── فاصل ──
                            Container(
                              height: 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.transparent, gold.withOpacity(0.2), Colors.transparent],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── أزرار التواصل الاجتماعي ──
                            Row(
                              children: [
                                _buildSocialTile(
                                  icon: Icons.email_rounded,
                                  label: 'إيميل',
                                  color: const Color(0xFFEA4335),
                                  isDark: isDark,
                                ),
                                const SizedBox(width: 8),
                                _buildSocialTile(
                                  icon: Icons.facebook_rounded,
                                  label: 'فيسبوك',
                                  color: const Color(0xFF1877F2),
                                  isDark: isDark,
                                ),
                                const SizedBox(width: 8),
                                _buildSocialTile(
                                  icon: Icons.telegram_rounded,
                                  label: 'تيليغرام',
                                  color: const Color(0xFF229ED9),
                                  isDark: isDark,
                                ),
                                const SizedBox(width: 8),
                                _buildSocialTile(
                                  icon: Icons.chat_rounded,
                                  label: 'واتساب',
                                  color: const Color(0xFF25D366),
                                  isDark: isDark,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  USER AVATAR BUTTON (AppBar - Top Right)
// ─────────────────────────────────────────────

class _UserAvatarButton extends StatefulWidget {
  final bool isDark;
  const _UserAvatarButton({required this.isDark});

  @override
  State<_UserAvatarButton> createState() => _UserAvatarButtonState();
}

class _UserAvatarButtonState extends State<_UserAvatarButton>
    with SingleTickerProviderStateMixin {
  static const gold = Color(0xFFD4A017);
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  OverlayEntry? _overlayEntry;
  final GlobalKey _avatarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack);
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _removeOverlay();
    _animCtrl.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showPopup(BuildContext context, User? user) {
    if (_overlayEntry != null) {
      _animCtrl.reverse().then((_) => _removeOverlay());
      return;
    }

    final RenderBox renderBox =
        _avatarKey.currentContext!.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;
    final bool isDark = widget.isDark;

    _overlayEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          // Dismiss backdrop
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                _animCtrl.reverse().then((_) => _removeOverlay());
              },
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),
          ),
          // Popup
          Positioned(
            top: offset.dy + size.height + 8,
            left: offset.dx,
            child: AnimatedBuilder(
              animation: _animCtrl,
              builder: (_, child) => FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  alignment: Alignment.topRight,
                  child: child,
                ),
              ),
              child: _UserPopupCard(
                isDark: isDark,
                user: user,
                onClose: () {
                  _animCtrl.reverse().then((_) => _removeOverlay());
                },
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    _animCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final photoUrl = user?.photoURL;
        final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

        return GestureDetector(
          key: _avatarKey,
          onTap: () => _showPopup(context, user),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [gold.withOpacity(0.8), const Color(0xFF8A5E00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: gold.withOpacity(0.6),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: gold.withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipOval(
              child: hasPhoto
                  ? Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _DefaultAvatar(),
                    )
                  : _DefaultAvatar(),
            ),
          ),
        );
      },
    );
  }
}

class _DefaultAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/profile.png',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.person_rounded,
        color: Colors.white,
        size: 22,
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  USER POPUP CARD
// ─────────────────────────────────────────────

class _UserPopupCard extends StatelessWidget {
  final bool isDark;
  final User? user;
  final VoidCallback onClose;

  const _UserPopupCard({
    required this.isDark,
    required this.user,
    required this.onClose,
  });

  static const gold = Color(0xFFD4A017);

  Future<void> _signInWithGoogle(BuildContext context) async {
    onClose();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('فشل تسجيل الدخول: $e')),
      );
    }
  }

  Future<void> _signOut(BuildContext context) async {
    onClose();
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'غير معروف';
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = user != null;
    final cardBg = isDark ? const Color(0xFF141414) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white54 : Colors.black45;
    final photoUrl = user?.photoURL;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    final joinDate = user?.metadata.creationTime;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Arrow pointer ──
            Positioned(
              top: -9,
              left: 10,
              child: CustomPaint(
                painter: _ArrowPainter(
                  color: isDark
                      ? const Color(0xFF1E1E1E)
                      : const Color(0xFFFFFDF7),
                  borderColor: gold.withOpacity(0.3),
                ),
                size: const Size(18, 10),
              ),
            ),
            // ── Main card ──
            Container(
              width: 240,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: gold.withOpacity(0.25), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.55 : 0.14),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: gold.withOpacity(0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoggedIn) ...[
                    // ── Header gradient ──
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(22)),
                        gradient: LinearGradient(
                          colors: isDark
                              ? [
                                  const Color(0xFF1E1A0A),
                                  const Color(0xFF141414),
                                ]
                              : [
                                  const Color(0xFFFFF9EC),
                                  const Color(0xFFFFFDF7),
                                ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        border: Border(
                          bottom: BorderSide(
                              color: gold.withOpacity(0.15), width: 0.8),
                        ),
                      ),
                      child: Row(
                        children: [
                          // ── Avatar ──
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFFE8B84B), Color(0xFF8A5E00)],
                              ),
                              border: Border.all(
                                  color: gold.withOpacity(0.6), width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: gold.withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: hasPhoto
                                  ? Image.network(
                                      photoUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.person_rounded,
                                              color: Colors.white, size: 28),
                                    )
                                  : const Icon(Icons.person_rounded,
                                      color: Colors.white, size: 28),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.displayName ?? 'مستخدم',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  user?.email ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textSub,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Join date ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: gold.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.calendar_today_rounded,
                                color: gold, size: 16),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تاريخ الانضمام',
                                style: TextStyle(
                                    color: textSub,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatDate(joinDate),
                                style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // ── Divider ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                      child: Container(
                        height: 0.8,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Colors.transparent,
                            gold.withOpacity(0.25),
                            Colors.transparent,
                          ]),
                        ),
                      ),
                    ),
                    // ── Sign out button ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      child: GestureDetector(
                        onTap: () => _signOut(context),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.red.withOpacity(0.25), width: 1),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.logout_rounded,
                                  color: Colors.red.shade400, size: 17),
                              const SizedBox(width: 7),
                              Text(
                                'تسجيل الخروج',
                                style: TextStyle(
                                  color: Colors.red.shade400,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // ── Not logged in ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: gold.withOpacity(0.12),
                              border: Border.all(
                                  color: gold.withOpacity(0.3), width: 2),
                            ),
child: ClipOval(
  child: Image.asset(
    'assets/images/profile.png',
    fit: BoxFit.cover,
    errorBuilder: (_, __, ___) => const Icon(
        Icons.person_rounded,
        color: gold,
        size: 26),
  ),
),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'زائر',
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'سجّل دخولك للوصول إلى جميع المزايا',
                                  style: TextStyle(
                                      color: textSub, fontSize: 11, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Divider ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Container(
                        height: 0.8,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Colors.transparent,
                            gold.withOpacity(0.25),
                            Colors.transparent,
                          ]),
                        ),
                      ),
                    ),
                    // ── Sign in button ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                      child: GestureDetector(
                        onTap: () => _signInWithGoogle(context),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [ui.Color.fromARGB(255, 0, 110, 255), ui.Color.fromARGB(255, 23, 89, 212)],                              end: Alignment.bottomLeft,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const ui.Color.fromARGB(120, 23, 89, 212).withOpacity(0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.g_mobiledata_rounded,
                                    color: ui.Color.fromARGB(255, 23, 89, 212), size: 18),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'تسجيل الدخول بـ Google',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  ARROW PAINTER (popup pointer)
// ─────────────────────────────────────────────

class _ArrowPainter extends CustomPainter {
  final Color color;
  final Color borderColor;
  const _ArrowPainter({required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill;
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(borderPath, borderPaint);

    final fillPath = Path()
      ..moveTo(1.5, size.height)
      ..lineTo(size.width / 2, 1.5)
      ..lineTo(size.width - 1.5, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.color != color || old.borderColor != borderColor;
}