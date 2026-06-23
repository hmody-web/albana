import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../firebase_notification_service.dart';
import '../widgets/shared_widgets.dart';

SystemUiOverlayStyle settingsSystemUiOverlayStyle(bool isDark) {
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: isDark ? const Color(0xFF050505) : const Color(0xFFF7F4EE),
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
  );
}

void applySettingsSystemUiOverlayStyle(bool isDark) {
  SystemChrome.setSystemUIOverlayStyle(settingsSystemUiOverlayStyle(isDark));
}

class SettingsPage extends StatefulWidget {
  final bool isDark;
  final ValueChanged<bool> onThemeToggle;

  const SettingsPage({
    super.key,
    required this.isDark,
    required this.onThemeToggle,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  static const gold = Color(0xFFD4A017);
  static const _privacyUrl = 'https://majidalbana.com/privacy_policy.html';
  static const _deleteAccountDataUrl = 'https://majidalbana.com/admin/account/delete_account_data.php';
  static const _supportEmail = 'support@majidalbana.com';

  bool _deletingAccount = false;
  bool _loadingNotificationPrefs = true;
  bool _systemNotificationsEnabled = true;
  Map<String, bool> _notificationPrefs = const {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    applySettingsSystemUiOverlayStyle(widget.isDark);
    _loadNotificationSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadNotificationSettings(silent: true);
    }
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDark != widget.isDark) {
      applySettingsSystemUiOverlayStyle(widget.isDark);
    }
  }

  bool _isSupervisor(User? user) {
    final email = user?.email?.trim().toLowerCase();
    return email == 'hmode.qq@gmail.com' || email == 'hmode.qu@gmail.com';
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
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
      messenger.showSnackBar(SnackBar(content: Text('فشل تسجيل الدخول: $e')));
    }
  }

  Future<void> _signOut() async {
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _launchExternal(String rawUrl) async {
    final uri = Uri.parse(rawUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الرابط')),
      );
    }
  }

  Future<void> _openSupportEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {
        'subject': 'الدعم الفني - تطبيق ماجد البنا',
      },
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح البريد الإلكتروني')),
      );
    }
  }

  Future<bool> _confirmDialog({
    required String title,
    required String message,
    required String confirmText,
    required IconData icon,
    Color confirmColor = gold,
  }) async {
    final isDark = widget.isDark;
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: title,
      barrierColor: Colors.black.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: MediaQuery.of(dialogContext).size.width * 0.86,
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF151515) : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.08) : gold.withOpacity(0.18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.45 : 0.16),
                      blurRadius: 32,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [confirmColor.withOpacity(0.78), confirmColor],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: confirmColor.withOpacity(0.24),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(icon, color: Colors.white, size: 31),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1A1000),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 13,
                        height: 1.55,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(dialogContext).pop(false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark ? Colors.white70 : const Color(0xFF6B4200),
                                side: BorderSide(
                                  color: isDark ? Colors.white.withOpacity(0.12) : gold.withOpacity(0.30),
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: const Text(
                                'إلغاء',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(dialogContext).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: confirmColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: Text(
                                confirmText,
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    return result == true;
  }

  Future<void> _showSignOutConfirmation() async {
    final confirmed = await _confirmDialog(
      title: 'تأكيد تسجيل الخروج',
      message: 'هل ترغب بتسجيل الخروج من حسابك؟ لن يتم حذف أي بيانات محفوظة داخل التطبيق.',
      confirmText: 'تسجيل الخروج',
      icon: Icons.logout_rounded,
    );
    if (confirmed) await _signOut();
  }

  Future<void> _deleteServerAccountData(User user) async {
    final response = await http
        .post(
          Uri.parse(_deleteAccountDataUrl),
          body: {
            'email': user.email ?? '',
            'uid': user.uid,
          },
        )
        .timeout(const Duration(seconds: 25));

    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}

    if (response.statusCode < 200 || response.statusCode >= 300 || data['success'] != true) {
      final message = (data['message'] ?? 'فشل حذف بيانات الحساب من الخادم').toString();
      throw Exception(message);
    }
  }

  Future<void> _deleteFirebaseAccount(User user) async {
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login') rethrow;

      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        throw Exception('يجب تسجيل الدخول مرة أخرى لتأكيد حذف الحساب.');
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(credential);
      await FirebaseAuth.instance.currentUser?.delete();
    }
  }

  Future<void> _clearLocalAppData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<void> _deleteAccountCompletely() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب تسجيل الدخول أولاً.')),
      );
      return;
    }

    final confirmed = await _confirmDialog(
      title: 'مسح بيانات الحساب',
      message: 'سيتم حذف تعليقاتك وإعجاباتك وبيانات التسجيل والحضور المرتبطة بحسابك من الخادم، ثم حذف حساب تسجيل الدخول من التطبيق. لا يمكن التراجع عن هذه العملية.',
      confirmText: 'حذف البيانات',
      icon: Icons.delete_forever_rounded,
      confirmColor: const Color(0xFFE53935),
    );
    if (!confirmed || _deletingAccount) return;

    setState(() => _deletingAccount = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _deleteServerAccountData(user);
      await _deleteFirebaseAccount(user);
      await GoogleSignIn().signOut();
      await _clearLocalAppData();
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('تم حذف بيانات الحساب بنجاح.')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر حذف الحساب: $e')),
      );
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }


  Future<void> _loadNotificationSettings({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loadingNotificationPrefs = true);
    }

    final prefs = await FirebaseNotificationService.loadNotificationPreferences();
    final systemEnabled = await FirebaseNotificationService.areSystemNotificationsEnabled();

    if (!mounted) return;
    setState(() {
      _notificationPrefs = prefs;
      _systemNotificationsEnabled = systemEnabled;
      _loadingNotificationPrefs = false;
    });
  }

  bool get _generalNotificationsEnabled =>
      (_notificationPrefs[FirebaseNotificationService.generalNotificationsKey] ?? true) &&
      _systemNotificationsEnabled;

  int get _enabledNotificationSections {
    final keys = [
      FirebaseNotificationService.postsNotificationsKey,
      FirebaseNotificationService.engineeringFilesNotificationsKey,
      FirebaseNotificationService.structuralPlansNotificationsKey,
      FirebaseNotificationService.lecturesNotificationsKey,
    ];
    return keys.where((key) => _notificationPrefs[key] ?? true).length;
  }

  Future<void> _handleSystemNotificationsDisabled() async {
    HapticFeedback.selectionClick();
    final opened = await FirebaseNotificationService.openSystemNotificationSettings();
    if (!opened) {
      final allowed = await FirebaseNotificationService.requestNotificationPermission();
      if (!allowed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الإشعارات غير مفعلة من إعدادات النظام. فعّلها من إعدادات التطبيق.'),
          ),
        );
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _loadNotificationSettings(silent: true);
  }

  Future<void> _setNotificationPref(String key, bool value) async {
    if (key == FirebaseNotificationService.generalNotificationsKey && value && !_systemNotificationsEnabled) {
      await _handleSystemNotificationsDisabled();
      if (!_systemNotificationsEnabled) return;
    }

    if (key != FirebaseNotificationService.generalNotificationsKey &&
        value &&
        !_generalNotificationsEnabled) {
      await FirebaseNotificationService.setNotificationPreference(
        FirebaseNotificationService.generalNotificationsKey,
        true,
      );
      if (!_systemNotificationsEnabled) {
        await _handleSystemNotificationsDisabled();
      }
    }

    await FirebaseNotificationService.setNotificationPreference(key, value);
    await _loadNotificationSettings(silent: true);
  }

  void _openNotificationsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.48),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            Future<void> updatePref(String key, bool value) async {
              await _setNotificationPref(key, value);
              if (context.mounted) sheetSetState(() {});
            }

            final isDark = widget.isDark;
            final cardBg = isDark ? const Color(0xFF121212) : Colors.white;
            final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
            final textSub = isDark ? Colors.white60 : Colors.black54;
            final generalLocal = _notificationPrefs[FirebaseNotificationService.generalNotificationsKey] ?? true;
            final generalEnabled = generalLocal && _systemNotificationsEnabled;

            return Directionality(
              textDirection: TextDirection.rtl,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  16 + MediaQuery.of(context).padding.bottom,
                ),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: gold.withOpacity(0.16)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.50 : 0.18),
                      blurRadius: 30,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: gold.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: const Icon(Icons.notifications_active_rounded, color: gold, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'إعدادات الإشعارات',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _systemNotificationsEnabled
                                    ? 'تحكم بالإشعارات العامة وكل قسم بشكل مستقل.'
                                    : 'الإشعارات مغلقة من إعدادات الجهاز. التقنية تحب التعقيد طبعاً.',
                                style: TextStyle(
                                  color: textSub,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!_systemNotificationsEnabled)
                      _NotificationWarningCard(
                        isDark: isDark,
                        onTap: () async {
                          await _handleSystemNotificationsDisabled();
                          if (context.mounted) sheetSetState(() {});
                        },
                      ),
                    if (!_systemNotificationsEnabled) const SizedBox(height: 10),
                    _NotificationSwitchRow(
                      isDark: isDark,
                      icon: Icons.notifications_rounded,
                      title: 'كل الإشعارات',
                      subtitle: _systemNotificationsEnabled
                          ? 'إيقافها يلغي استقبال جميع إشعارات التطبيق من داخل التطبيق.'
                          : 'اضغط للتفعيل من إعدادات التطبيق أولاً.',
                      value: generalEnabled,
                      enabled: true,
                      onChanged: (value) async {
                        if (!_systemNotificationsEnabled && value) {
                          await _handleSystemNotificationsDisabled();
                          if (context.mounted) sheetSetState(() {});
                          return;
                        }
                        await updatePref(FirebaseNotificationService.generalNotificationsKey, value);
                      },
                    ),
                    const SizedBox(height: 10),
                    _NotificationSwitchRow(
                      isDark: isDark,
                      icon: Icons.article_rounded,
                      title: 'إشعارات المنشورات',
                      subtitle: 'تنبيه عند إضافة منشور جديد.',
                      value: _notificationPrefs[FirebaseNotificationService.postsNotificationsKey] ?? true,
                      enabled: generalEnabled,
                      onChanged: (value) => updatePref(FirebaseNotificationService.postsNotificationsKey, value),
                    ),
                    const SizedBox(height: 8),
                    _NotificationSwitchRow(
                      isDark: isDark,
                      icon: Icons.picture_as_pdf_rounded,
                      title: 'إشعارات الملفات الهندسية',
                      subtitle: 'تنبيه عند إضافة ملفات ومواد هندسية.',
                      value: _notificationPrefs[FirebaseNotificationService.engineeringFilesNotificationsKey] ?? true,
                      enabled: generalEnabled,
                      onChanged: (value) => updatePref(FirebaseNotificationService.engineeringFilesNotificationsKey, value),
                    ),
                    const SizedBox(height: 8),
                    _NotificationSwitchRow(
                      isDark: isDark,
                      icon: Icons.architecture_rounded,
                      title: 'إشعارات المخططات الإنشائية',
                      subtitle: 'تنبيه خاص بالمخططات الإنشائية عند توفرها.',
                      value: _notificationPrefs[FirebaseNotificationService.structuralPlansNotificationsKey] ?? true,
                      enabled: generalEnabled,
                      onChanged: (value) => updatePref(FirebaseNotificationService.structuralPlansNotificationsKey, value),
                    ),
                    const SizedBox(height: 8),
                    _NotificationSwitchRow(
                      isDark: isDark,
                      icon: Icons.school_rounded,
                      title: 'إشعارات المحاضرات',
                      subtitle: 'تنبيه عند إضافة أو تحديث محاضرة.',
                      value: _notificationPrefs[FirebaseNotificationService.lecturesNotificationsKey] ?? true,
                      enabled: generalEnabled,
                      onChanged: (value) => updatePref(FirebaseNotificationService.lecturesNotificationsKey, value),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }


  void _openNotificationsPage() {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => _NotificationsSettingsPage(isDark: widget.isDark),
          ),
        )
        .then((_) {
      if (mounted) {
        _loadNotificationSettings(silent: true);
      }
    });
  }

  void _openAboutPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AboutAppPage(isDark: widget.isDark),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) applySettingsSystemUiOverlayStyle(widget.isDark);
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: settingsSystemUiOverlayStyle(widget.isDark),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            PremiumAppBar(title: 'الإعدادات', isDark: widget.isDark),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  StreamBuilder<User?>(
                    stream: FirebaseAuth.instance.authStateChanges(),
                    builder: (context, snapshot) {
                      final user = snapshot.data;
                      return _ModernLoginCard(
                        isDark: widget.isDark,
                        user: user,
                        isSupervisor: _isSupervisor(user),
                        onLogin: () => _signInWithGoogle(context),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  _SettingsSection(
                    isDark: widget.isDark,
                    title: 'المظهر',
                    children: [
                      _SettingsActionTile(
                        isDark: widget.isDark,
                        icon: widget.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                        title: 'مظهر التطبيق',
                        trailing: _ThemeSwitch(
                          isDark: widget.isDark,
                          onChanged: () => widget.onThemeToggle(!widget.isDark),
                        ),
                        onTap: () => widget.onThemeToggle(!widget.isDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _SettingsSection(
                    isDark: widget.isDark,
                    title: 'الإشعارات',
                    children: [
                      _SettingsActionTile(
                        isDark: widget.isDark,
                        icon: Icons.notifications_active_outlined,
                        title: 'إعدادات الإشعارات',
                        trailing: _NotificationStatusBadge(
                          isDark: widget.isDark,
                          loading: _loadingNotificationPrefs,
                          enabled: _generalNotificationsEnabled,
                          enabledSections: _enabledNotificationSections,
                        ),
                        onTap: _openNotificationsPage,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _SettingsSection(
                    isDark: widget.isDark,
                    title: 'التواصل والدعم',
                    children: [
                      _SettingsActionTile(
                        isDark: widget.isDark,
                        icon: Icons.mail_outline_rounded,
                        title: 'الدعم الفني',
                        onTap: _openSupportEmail,
                      ),
                      _SettingsActionTile(
                        isDark: widget.isDark,
                        icon: Icons.info_outline_rounded,
                        title: 'عن التطبيق',
                        onTap: _openAboutPage,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _SettingsSection(
                    isDark: widget.isDark,
                    title: 'السياسات',
                    children: [
                      _SettingsActionTile(
                        isDark: widget.isDark,
                        icon: Icons.privacy_tip_outlined,
                        title: 'سياسة الخصوصية',
                        onTap: () => _launchExternal(_privacyUrl),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  StreamBuilder<User?>(
                    stream: FirebaseAuth.instance.authStateChanges(),
                    builder: (context, snapshot) {
                      final user = snapshot.data;
                      final loggedIn = user != null;
                      return _SettingsSection(
                        isDark: widget.isDark,
                        title: 'الحساب',
                        children: [
                          _SettingsActionTile(
                            isDark: widget.isDark,
                            icon: Icons.delete_forever_outlined,
                            title: _deletingAccount ? 'جاري مسح بيانات الحساب...' : 'مسح بيانات الحساب',
                            danger: true,
                            enabled: loggedIn && !_deletingAccount,
                            trailing: _deletingAccount
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : null,
                            onTap: _deleteAccountCompletely,
                          ),
                          _SettingsActionTile(
                            isDark: widget.isDark,
                            icon: loggedIn ? Icons.logout_rounded : Icons.login_rounded,
                            title: loggedIn ? 'تسجيل الخروج' : 'تسجيل الدخول بواسطة Google',
                            onTap: loggedIn ? _showSignOutConfirmation : () => _signInWithGoogle(context),
                          ),
                        ],
                      );
                    },
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutAppPage extends StatelessWidget {
  final bool isDark;

  const _AboutAppPage({required this.isDark});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF080808) : const Color(0xFFF7F4EE);
    final cardBg = isDark ? const Color(0xFF151515) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white70 : Colors.black54;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: settingsSystemUiOverlayStyle(isDark),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: bg,
          body: SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        Material(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            splashColor: gold.withOpacity(0.10),
                            highlightColor: gold.withOpacity(0.08),
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: gold.withOpacity(0.14)),
                              ),
                              child: const Icon(Icons.arrow_forward_ios_rounded, color: gold, size: 18),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'عن التطبيق',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          gradient: LinearGradient(
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                            colors: isDark
                                ? const [Color(0xFF211A0D), Color(0xFF151515), Color(0xFF090909)]
                                : const [Color(0xFFFFF7DC), Color(0xFFFFFFFF), Color(0xFFFFF1BD)],
                          ),
                          border: Border.all(color: gold.withOpacity(isDark ? 0.24 : 0.28)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(isDark ? 0.34 : 0.08),
                              blurRadius: 26,
                              offset: const Offset(0, 13),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 62,
                                  height: 62,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(22),
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFFFD86B), Color(0xFFD4A017)],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: gold.withOpacity(0.28),
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.school_rounded, color: Colors.white, size: 32),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'تطبيق ماجد البنا',
                                        style: TextStyle(
                                          color: textPrimary,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        'منصة تعليمية وتنظيمية متكاملة',
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
                            const SizedBox(height: 18),
                            Text(
                              'مرحباً بك في تطبيق ماجد البنا. تم تصميم هذا التطبيق ليكون منصة متكاملة تتيح للمستخدمين الوصول بسهولة إلى المحتوى والمنشورات والجداول والدورات التدريبية، مع توفير تجربة استخدام بسيطة وسريعة تساعد على متابعة كل جديد في مكان واحد.',
                              style: TextStyle(
                                color: textSub,
                                fontSize: 14,
                                height: 1.75,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _AboutInfoCard(
                        isDark: isDark,
                        title: 'هدف التطبيق',
                        icon: Icons.flag_rounded,
                        child: Text(
                          'يهدف التطبيق إلى تقديم المعلومات والخدمات التعليمية والتنظيمية بشكل واضح ومنظم، مع تحديث المحتوى بصورة مستمرة لضمان حصول المستخدمين على أحدث المنشورات والإعلانات والمواد المتاحة.',
                          style: TextStyle(color: textSub, fontSize: 13.5, height: 1.75, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _AboutInfoCard(
                        isDark: isDark,
                        title: 'مميزات التطبيق',
                        icon: Icons.auto_awesome_rounded,
                        child: Column(
                          children: [
                            _AboutFeatureItem(textColor: textSub, text: 'عرض المنشورات والمحتوى المحدث باستمرار.'),
                            _AboutFeatureItem(textColor: textSub, text: 'الاطلاع على الجداول والمحاضرات بطريقة منظمة.'),
                            _AboutFeatureItem(textColor: textSub, text: 'التسجيل في الدورات التدريبية ومتابعة بيانات التسجيل.'),
                            _AboutFeatureItem(textColor: textSub, text: 'إدارة الحضور وقوائم المشاركين في الدورات.'),
                            _AboutFeatureItem(textColor: textSub, text: 'التفاعل مع المنشورات والملفات عبر الإعجابات والتعليقات.'),
                            _AboutFeatureItem(textColor: textSub, text: 'الوصول إلى الملفات والمواد التعليمية بصيغة منظمة وسهلة.'),
                            _AboutFeatureItem(textColor: textSub, text: 'إشعارات للتحديثات والإعلانات والمحتوى الجديد.'),
                            _AboutFeatureItem(textColor: textSub, text: 'واجهة استخدام بسيطة وسريعة ومتوافقة مع طبيعة المحتوى.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _AboutInfoCard(
                        isDark: isDark,
                        title: 'تسجيل الدخول',
                        icon: Icons.login_rounded,
                        child: Text(
                          'يتم استخدام تسجيل الدخول عبر Google فقط عند الحاجة إلى التفاعل مع المحتوى، مثل إضافة التعليقات أو تسجيل الإعجاب بالمنشورات والملفات أو التسجيل في الدورات التدريبية، وذلك لضمان تجربة آمنة ومنظمة للمستخدمين.',
                          style: TextStyle(color: textSub, fontSize: 13.5, height: 1.75, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _AboutInfoCard(
                        isDark: isDark,
                        title: 'المحتوى والخدمات',
                        icon: Icons.apps_rounded,
                        child: Text(
                          'يوفر التطبيق أقساماً متعددة تشمل المنشورات، الملفات، الجداول، المحاضرات، الدورات التدريبية، الاستمارات، الحضور، وروابط التواصل الرسمية. ويتم تنظيم هذه الأقسام بما يساعد المستخدم على الوصول السريع إلى المحتوى المطلوب دون تعقيد.',
                          style: TextStyle(color: textSub, fontSize: 13.5, height: 1.75, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _AboutInfoCard(
                        isDark: isDark,
                        title: 'الخصوصية وحماية البيانات',
                        icon: Icons.privacy_tip_rounded,
                        child: Text(
                          'يراعي التطبيق خصوصية المستخدمين ويستخدم البيانات اللازمة فقط لتشغيل الميزات الأساسية، مثل تسجيل الدخول، التفاعل مع المحتوى، إدارة التسجيل في الدورات، وإرسال الإشعارات المهمة. يمكن للمستخدم مراجعة سياسة الخصوصية من صفحة الإعدادات في أي وقت.',
                          style: TextStyle(color: textSub, fontSize: 13.5, height: 1.75, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _AboutInfoCard(
                        isDark: isDark,
                        title: 'الدعم والتواصل',
                        icon: Icons.support_agent_rounded,
                        child: Text(
                          'نسعى إلى تطوير التطبيق وتحسينه بصورة مستمرة بما يخدم المستخدمين ويجعل الوصول إلى المحتوى والخدمات أكثر سهولة وتنظيماً. يمكن التواصل مع الدعم الفني عبر البريد الإلكتروني support@majidalbana.com أو من خلال قنوات التواصل الرسمية داخل التطبيق.',
                          style: TextStyle(color: textSub, fontSize: 13.5, height: 1.75, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: gold.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: gold.withOpacity(0.16)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.verified_rounded, color: gold, size: 21),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'الإصدار 1.0.0',
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
                    ]),
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

class _AboutInfoCard extends StatelessWidget {
  final bool isDark;
  final String title;
  final IconData icon;
  final Widget child;

  const _AboutInfoCard({
    required this.isDark,
    required this.title,
    required this.icon,
    required this.child,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF151515) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: gold.withOpacity(0.13)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.22 : 0.045),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: gold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: gold, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
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

class _AboutFeatureItem extends StatelessWidget {
  final String text;
  final Color textColor;

  const _AboutFeatureItem({required this.text, required this.textColor});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: gold,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: textColor,
                fontSize: 13.5,
                height: 1.55,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModernLoginCard extends StatelessWidget {
  final bool isDark;
  final User? user;
  final bool isSupervisor;
  final VoidCallback onLogin;

  const _ModernLoginCard({
    required this.isDark,
    required this.user,
    required this.isSupervisor,
    required this.onLogin,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final loggedIn = user != null;
    final title = loggedIn ? (user!.displayName ?? 'مستخدم Google') : 'مرحباً بك';
    final subtitle = loggedIn ? (user!.email ?? 'حساب Google') : 'سجّل الدخول للاستفادة من مزايا المنصة';
    final role = loggedIn ? (isSupervisor ? 'مشرف' : 'عضو') : 'Google';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: isDark
              ? const [Color(0xFF1F1B12), Color(0xFF121212), Color(0xFF070707)]
              : const [Color(0xFFFFFBF0), Color(0xFFFFFFFF), Color(0xFFFFF3C9)],
        ),
        border: Border.all(color: gold.withOpacity(isDark ? 0.22 : 0.26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.34 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            end: -34,
            top: -42,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: gold.withOpacity(0.10),
              ),
            ),
          ),
          PositionedDirectional(
            start: -22,
            bottom: -32,
            child: Container(
              width: 105,
              height: 105,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: gold.withOpacity(0.07),
              ),
            ),
          ),
          Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD86B), Color(0xFFD4A017)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: gold.withOpacity(0.25),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      backgroundColor: isDark ? const Color(0xFF202020) : Colors.white,
                      backgroundImage: loggedIn && user!.photoURL != null && user!.photoURL!.isNotEmpty
                          ? NetworkImage(user!.photoURL!)
                          : null,
                      child: !loggedIn
                          ? const Icon(Icons.person_rounded, color: gold, size: 34)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF1A1000),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: gold.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: gold.withOpacity(0.18)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          loggedIn
                              ? (isSupervisor ? Icons.admin_panel_settings_rounded : Icons.verified_rounded)
                              : Icons.account_circle_rounded,
                          color: gold,
                          size: 17,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          role,
                          style: const TextStyle(
                            color: gold,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (!loggedIn)
                    _SmallGoldButton(
                      label: 'تسجيل الدخول',
                      icon: Icons.login_rounded,
                      onTap: onLogin,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallGoldButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SmallGoldButton({required this.label, required this.icon, required this.onTap});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: gold,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.white.withOpacity(0.18),
        highlightColor: Colors.white.withOpacity(0.10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: Colors.white),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final bool isDark;
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.isDark,
    required this.title,
    required this.children,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF151515) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1000);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: gold.withOpacity(0.14)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.22 : 0.045),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 58,
                    endIndent: 14,
                    color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.055),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool danger;
  final bool enabled;

  const _SettingsActionTile({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
    this.danger = false,
    this.enabled = true,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final activeColor = danger ? const Color(0xFFE53935) : gold;
    final titleColor = danger
        ? const Color(0xFFE53935)
        : (isDark ? Colors.white : const Color(0xFF1A1000));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        splashColor: activeColor.withOpacity(0.08),
        highlightColor: activeColor.withOpacity(0.07),
        hoverColor: activeColor.withOpacity(0.045),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: activeColor.withOpacity(0.11),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: activeColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                trailing ?? Icon(Icons.arrow_back_ios_new_rounded, color: activeColor, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _NotificationsSettingsPage extends StatefulWidget {
  final bool isDark;

  const _NotificationsSettingsPage({required this.isDark});

  @override
  State<_NotificationsSettingsPage> createState() => _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState extends State<_NotificationsSettingsPage>
    with WidgetsBindingObserver {
  static const gold = Color(0xFFD4A017);

  bool _loading = true;
  bool _systemNotificationsEnabled = true;
  Map<String, bool> _prefs = const {};
  final Set<String> _pendingKeys = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    applySettingsSystemUiOverlayStyle(widget.isDark);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(silent: true);
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loading = true);
    }

    final prefs = await FirebaseNotificationService.loadNotificationPreferences();
    final systemEnabled = await FirebaseNotificationService.areSystemNotificationsEnabled();

    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _systemNotificationsEnabled = systemEnabled;
      _loading = false;
    });
  }

  bool get _generalLocal =>
      _prefs[FirebaseNotificationService.generalNotificationsKey] ?? true;

  bool get _generalEnabled => _generalLocal && _systemNotificationsEnabled;

  bool get _filesEnabled =>
      FirebaseNotificationService.areAllFileCategoriesEnabled(_prefs);

  int get _enabledFileCategories =>
      FirebaseNotificationService.enabledFileCategoriesCount(_prefs);

  Future<void> _openSystemSettings() async {
    HapticFeedback.selectionClick();
    final opened = await FirebaseNotificationService.openSystemNotificationSettings();
    if (!opened) {
      final allowed = await FirebaseNotificationService.requestNotificationPermission();
      if (!allowed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الإشعارات غير مفعلة من إعدادات النظام. فعّلها من إعدادات التطبيق.'),
          ),
        );
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _load(silent: true);
  }

  void _setFast(String key, bool value) {
    HapticFeedback.selectionClick();

    if (key == FirebaseNotificationService.generalNotificationsKey &&
        value &&
        !_systemNotificationsEnabled) {
      _openSystemSettings();
      return;
    }

    final previousPrefs = Map<String, bool>.from(_prefs);

    setState(() {
      final next = Map<String, bool>.from(_prefs);

      if (key != FirebaseNotificationService.generalNotificationsKey &&
          value &&
          !_generalLocal) {
        next[FirebaseNotificationService.generalNotificationsKey] = true;
        _pendingKeys.add(FirebaseNotificationService.generalNotificationsKey);
      }

      if (key == FirebaseNotificationService.engineeringFilesNotificationsKey) {
        next[key] = value;
        for (final categoryKey in FirebaseNotificationService.fileCategoryPreferenceKeys) {
          next[categoryKey] = value;
          _pendingKeys.add(categoryKey);
        }
      } else {
        next[key] = value;
        if (FirebaseNotificationService.fileCategoryPreferenceKeys.contains(key)) {
          final allEnabled = FirebaseNotificationService.fileCategoryPreferenceKeys
              .every((categoryKey) => next[categoryKey] ?? true);
          next[FirebaseNotificationService.engineeringFilesNotificationsKey] = allEnabled;
        }
      }

      _prefs = next;
      _pendingKeys.add(key);
    });

    Future<void>(() async {
      try {
        if (key != FirebaseNotificationService.generalNotificationsKey &&
            value &&
            (previousPrefs[FirebaseNotificationService.generalNotificationsKey] ?? true) == false) {
          await FirebaseNotificationService.setNotificationPreference(
            FirebaseNotificationService.generalNotificationsKey,
            true,
          );
        }

        await FirebaseNotificationService.setNotificationPreference(key, value);
      } catch (_) {
        if (!mounted) return;
        setState(() => _prefs = previousPrefs);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحديث إعدادات الإشعارات. تأكد من الاتصال ثم حاول مجدداً.')),
        );
      } finally {
        if (!mounted) return;
        setState(() {
          _pendingKeys.remove(key);
          if (key != FirebaseNotificationService.generalNotificationsKey) {
            _pendingKeys.remove(FirebaseNotificationService.generalNotificationsKey);
          }
          if (key == FirebaseNotificationService.engineeringFilesNotificationsKey) {
            _pendingKeys.removeAll(FirebaseNotificationService.fileCategoryPreferenceKeys);
          }
        });
        await _load(silent: true);
      }
    });
  }

  void _openFileNotificationsPage() {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => _FileNotificationsSettingsPage(
              isDark: widget.isDark,
              systemNotificationsEnabled: _systemNotificationsEnabled,
              generalEnabled: _generalEnabled,
            ),
          ),
        )
        .then((_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final pageBg = isDark ? const Color(0xFF050505) : const Color(0xFFF7F4EE);
    final cardBg = isDark ? const Color(0xFF121212) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white60 : Colors.black54;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: settingsSystemUiOverlayStyle(isDark),
        child: Scaffold(
          backgroundColor: pageBg,
          appBar: AppBar(
            backgroundColor: pageBg,
            elevation: 0,
            centerTitle: true,
            iconTheme: IconThemeData(color: textPrimary),
            title: Text(
              'إعدادات الإشعارات',
              style: TextStyle(
                color: textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator(color: gold))
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    24 + MediaQuery.of(context).padding.bottom,
                  ),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: gold.withOpacity(0.16)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.36 : 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: gold.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Icon(Icons.notifications_active_rounded, color: gold, size: 26),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'التحكم الكامل بالإشعارات',
                                      style: TextStyle(
                                        color: textPrimary,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      _systemNotificationsEnabled
                                          ? 'اختر الإشعارات التي تريد استقبالها من التطبيق.'
                                          : 'الإشعارات مغلقة من إعدادات الجهاز، لذلك يجب تفعيلها أولاً من النظام.',
                                      style: TextStyle(
                                        color: textSub,
                                        fontSize: 12.5,
                                        height: 1.45,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_pendingKeys.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: gold),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'يتم حفظ التغييرات بالخلفية...',
                                  style: TextStyle(
                                    color: textSub,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (!_systemNotificationsEnabled) ...[
                      _NotificationWarningCard(
                        isDark: isDark,
                        onTap: _openSystemSettings,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _NotificationSwitchRow(
                      isDark: isDark,
                      icon: Icons.notifications_active_rounded,
                      title: 'كل الإشعارات',
                      subtitle: _systemNotificationsEnabled
                          ? 'إيقافها يلغي استقبال جميع إشعارات التطبيق من داخل التطبيق.'
                          : 'فعّل إشعارات النظام أولاً حتى يعمل هذا الخيار.',
                      value: _generalLocal && _systemNotificationsEnabled,
                      enabled: _systemNotificationsEnabled,
                      onChanged: (value) => _setFast(FirebaseNotificationService.generalNotificationsKey, value),
                    ),
                    const SizedBox(height: 10),
                    _NotificationSwitchRow(
                      isDark: isDark,
                      icon: Icons.article_rounded,
                      title: 'إشعارات المنشورات',
                      subtitle: 'تنبيه عند إضافة منشور جديد.',
                      value: _prefs[FirebaseNotificationService.postsNotificationsKey] ?? true,
                      enabled: _generalEnabled,
                      onChanged: (value) => _setFast(FirebaseNotificationService.postsNotificationsKey, value),
                    ),
                    const SizedBox(height: 10),
                    _NotificationNavigationRow(
                      isDark: isDark,
                      icon: Icons.picture_as_pdf_rounded,
                      title: 'إشعارات الملفات الهندسية',
                      subtitle: _filesEnabled
                          ? 'كل تصنيفات الملفات مفعلة. اضغط للتحكم بكل تصنيف.'
                          : 'مفعل $_enabledFileCategories من ${FirebaseNotificationService.fileCategoryPreferenceKeys.length} تصنيف. اضغط للتفاصيل.',
                      enabled: _generalEnabled,
                      onTap: _generalEnabled ? _openFileNotificationsPage : null,
                    ),
                    const SizedBox(height: 10),
                    _NotificationSwitchRow(
                      isDark: isDark,
                      icon: Icons.school_rounded,
                      title: 'إشعارات المحاضرات',
                      subtitle: 'تنبيه عند إضافة محاضرة جديدة.',
                      value: _prefs[FirebaseNotificationService.lecturesNotificationsKey] ?? true,
                      enabled: _generalEnabled,
                      onChanged: (value) => _setFast(FirebaseNotificationService.lecturesNotificationsKey, value),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _FileNotificationsSettingsPage extends StatefulWidget {
  final bool isDark;
  final bool systemNotificationsEnabled;
  final bool generalEnabled;

  const _FileNotificationsSettingsPage({
    required this.isDark,
    required this.systemNotificationsEnabled,
    required this.generalEnabled,
  });

  @override
  State<_FileNotificationsSettingsPage> createState() => _FileNotificationsSettingsPageState();
}

class _FileNotificationsSettingsPageState extends State<_FileNotificationsSettingsPage> {
  static const gold = Color(0xFFD4A017);

  bool _loading = true;
  Map<String, bool> _prefs = const {};
  final Set<String> _pendingKeys = <String>{};

  bool get _generalEnabled =>
      widget.systemNotificationsEnabled &&
      (_prefs[FirebaseNotificationService.generalNotificationsKey] ?? widget.generalEnabled);

  bool get _allFilesEnabled =>
      FirebaseNotificationService.areAllFileCategoriesEnabled(_prefs);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    final prefs = await FirebaseNotificationService.loadNotificationPreferences();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _loading = false;
    });
  }

  void _setFast(String key, bool value) {
    HapticFeedback.selectionClick();
    final previousPrefs = Map<String, bool>.from(_prefs);

    setState(() {
      final next = Map<String, bool>.from(_prefs);
      if (key == FirebaseNotificationService.engineeringFilesNotificationsKey) {
        next[key] = value;
        for (final categoryKey in FirebaseNotificationService.fileCategoryPreferenceKeys) {
          next[categoryKey] = value;
          _pendingKeys.add(categoryKey);
        }
      } else {
        next[key] = value;
        final allEnabled = FirebaseNotificationService.fileCategoryPreferenceKeys
            .every((categoryKey) => next[categoryKey] ?? true);
        next[FirebaseNotificationService.engineeringFilesNotificationsKey] = allEnabled;
      }
      _prefs = next;
      _pendingKeys.add(key);
    });

    Future<void>(() async {
      try {
        await FirebaseNotificationService.setNotificationPreference(key, value);
      } catch (_) {
        if (!mounted) return;
        setState(() => _prefs = previousPrefs);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحديث إشعارات الملفات. حاول مرة أخرى.')),
        );
      } finally {
        if (!mounted) return;
        setState(() {
          _pendingKeys.remove(key);
          if (key == FirebaseNotificationService.engineeringFilesNotificationsKey) {
            _pendingKeys.removeAll(FirebaseNotificationService.fileCategoryPreferenceKeys);
          }
        });
        await _load(silent: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final pageBg = isDark ? const Color(0xFF050505) : const Color(0xFFF7F4EE);
    final cardBg = isDark ? const Color(0xFF121212) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white60 : Colors.black54;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: settingsSystemUiOverlayStyle(isDark),
        child: Scaffold(
          backgroundColor: pageBg,
          appBar: AppBar(
            backgroundColor: pageBg,
            elevation: 0,
            centerTitle: true,
            iconTheme: IconThemeData(color: textPrimary),
            title: Text(
              'إشعارات الملفات الهندسية',
              style: TextStyle(
                color: textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator(color: gold))
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    24 + MediaQuery.of(context).padding.bottom,
                  ),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: gold.withOpacity(0.16)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.36 : 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: gold.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(Icons.folder_copy_rounded, color: gold, size: 26),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'تحكم بتصنيفات الملفات',
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'يمكنك إيقاف إشعارات كل الملفات أو إيقاف تصنيف محدد فقط.',
                                  style: TextStyle(
                                    color: textSub,
                                    fontSize: 12.5,
                                    height: 1.45,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_pendingKeys.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2, color: gold),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'يتم حفظ تغييرات الملفات بالخلفية...',
                            style: TextStyle(
                              color: textSub,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    _NotificationSwitchRow(
                      isDark: isDark,
                      icon: Icons.all_inbox_rounded,
                      title: 'كل إشعارات الملفات',
                      subtitle: 'إيقافها يلغي إشعارات جميع تصنيفات الملفات الهندسية.',
                      value: _allFilesEnabled,
                      enabled: _generalEnabled,
                      onChanged: (value) => _setFast(FirebaseNotificationService.engineeringFilesNotificationsKey, value),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'تصنيفات الملفات',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...FirebaseNotificationService.defaultFileCategories.map((category) {
                      final key = FirebaseNotificationService.fileCategoryPreferenceKey(category);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _NotificationSwitchRow(
                          isDark: isDark,
                          icon: category == 'المخططات الأنشائية'
                              ? Icons.architecture_rounded
                              : Icons.folder_rounded,
                          title: category,
                          subtitle: category == 'المخططات الأنشائية'
                              ? 'تنبيه فقط عند إضافة ملف ضمن المخططات الإنشائية.'
                              : 'تنبيه عند إضافة ملف ضمن هذا التصنيف.',
                          value: _prefs[key] ?? true,
                          enabled: _generalEnabled,
                          onChanged: (value) => _setFast(key, value),
                        ),
                      );
                    }),
                  ],
                ),
        ),
      ),
    );
  }
}

class _NotificationNavigationRow extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  const _NotificationNavigationRow({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white60 : Colors.black54;
    final bg = isDark ? const Color(0xFF191919) : const Color(0xFFF9F5EA);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.48,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(20),
          splashColor: gold.withOpacity(0.08),
          highlightColor: gold.withOpacity(0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: gold, size: 21),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textSub,
                          fontSize: 11.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.arrow_back_ios_new_rounded, color: gold, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationStatusBadge extends StatelessWidget {
  final bool isDark;
  final bool loading;
  final bool enabled;
  final int enabledSections;

  const _NotificationStatusBadge({
    required this.isDark,
    required this.loading,
    required this.enabled,
    required this.enabledSections,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: gold),
      );
    }

    final color = enabled ? const Color(0xFF1B8F4D) : const Color(0xFFE53935);
    final label = enabled ? 'مفعل $enabledSections/4' : 'متوقف';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _NotificationWarningCard extends StatelessWidget {
  final bool isDark;
  final Future<void> Function() onTap;

  const _NotificationWarningCard({required this.isDark, required this.onTap});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: gold.withOpacity(0.10),
        highlightColor: gold.withOpacity(0.07),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: gold.withOpacity(0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: gold.withOpacity(0.22)),
          ),
          child: Row(
            children: [
              const Icon(Icons.settings_suggest_rounded, color: gold, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'الإشعارات غير مفعلة من النظام. اضغط هنا للانتقال إلى إعدادات التطبيق وتفعيلها.',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : const Color(0xFF5A3A00),
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_back_ios_new_rounded, color: gold, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationSwitchRow extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _NotificationSwitchRow({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white60 : Colors.black54;
    final bg = isDark ? const Color(0xFF191919) : const Color(0xFFF9F5EA);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.48,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: enabled ? () => onChanged(!value) : null,
          borderRadius: BorderRadius.circular(20),
          splashColor: gold.withOpacity(0.08),
          highlightColor: gold.withOpacity(0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: gold, size: 21),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textSub,
                          fontSize: 11.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _GoldSwitch(
                  value: value,
                  enabled: enabled,
                  onChanged: () => onChanged(!value),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoldSwitch extends StatelessWidget {
  final bool value;
  final bool enabled;
  final VoidCallback onChanged;

  const _GoldSwitch({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onChanged : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeInOut,
        width: 48,
        height: 27,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: value && enabled ? gold : Colors.grey.shade400,
          boxShadow: value && enabled
              ? [BoxShadow(color: gold.withOpacity(0.28), blurRadius: 10)]
              : [],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 21,
            height: 21,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              value ? Icons.check_rounded : Icons.close_rounded,
              color: value && enabled ? gold : Colors.grey,
              size: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeSwitch extends StatelessWidget {
  final bool isDark;
  final VoidCallback onChanged;

  const _ThemeSwitch({required this.isDark, required this.onChanged});

  static const gold = Color(0xFFD4A017);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOut,
        width: 48,
        height: 27,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: isDark ? gold : Colors.grey.shade300,
          boxShadow: isDark
              ? [BoxShadow(color: gold.withOpacity(0.32), blurRadius: 10)]
              : [],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
          alignment: isDark ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 21,
            height: 21,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              color: isDark ? gold : Colors.orange,
              size: 13,
            ),
          ),
        ),
      ),
    );
  }
}
