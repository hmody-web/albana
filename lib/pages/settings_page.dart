import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/shared_widgets.dart';

class SettingsPage extends StatelessWidget {
  final bool isDark;
  final ValueChanged<bool> onThemeToggle;
  const SettingsPage(
      {super.key, required this.isDark, required this.onThemeToggle});

  static const gold = Color(0xFFD4A017);



  bool _isSupervisor(User? user) {
    final email = user?.email?.trim().toLowerCase();
    return email == 'hmode.qq@gmail.com' || email == 'hmode.qu@gmail.com';
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      final provider = GoogleAuthProvider();
      await FirebaseAuth.instance.signInWithProvider(provider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل تسجيل الدخول: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل تسجيل الخروج: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1000);
    final textSub = isDark ? Colors.white60 : Colors.black54;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        PremiumAppBar(title: 'الإعدادات', isDark: isDark),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // ── كرت تسجيل الدخول بجوجل ──
              StreamBuilder<User?>(
                stream: FirebaseAuth.instance.authStateChanges(),
                builder: (context, snapshot) {
                  final user = snapshot.data;
                  final isLoggedIn = user != null;
                  final isSupervisor = _isSupervisor(user);

                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: const LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          Color(0xFFFFD86B),
                          Color(0xFFD4A017),
                          Color(0xFF7A4A00),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: gold.withOpacity(0.35),
                          blurRadius: 24,
                          spreadRadius: 1,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: -22,
                          top: -24,
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.10),
                            ),
                          ),
                        ),
                        Positioned(
                          right: -18,
                          bottom: -30,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withOpacity(0.08),
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 70,
                                  height: 70,
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withOpacity(0.28),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.70),
                                      width: 2,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    backgroundColor: Colors.white.withOpacity(0.18),
                                    backgroundImage: isLoggedIn &&
                                            user.photoURL != null &&
                                            user.photoURL!.isNotEmpty
                                        ? NetworkImage(user.photoURL!)
                                        : null,
                                    child: !isLoggedIn
                                        ? const Icon(
                                            Icons.person_rounded,
                                            color: Colors.white,
                                            size: 36,
                                          )
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isLoggedIn
                                            ? (user.displayName ?? 'مستخدم Google')
                                            : 'تسجيل الدخول',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        isLoggedIn
                                            ? (user.email ?? 'حساب Google')
                                            : 'ادخل بحساب Google للوصول إلى مزايا المنصة',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.88),
                                          height: 1.35,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.18),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isLoggedIn
                                          ? (isSupervisor ? Icons.admin_panel_settings_rounded : Icons.verified_rounded)
                                          : Icons.workspace_premium_rounded,
                                      color: const Color(0xFFD4A017),
                                      size: 19,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      isLoggedIn
                                          ? (isSupervisor
                                              ? 'مشرف في منصة د. ماجد البنا'
                                              : 'عضو في منصة د. ماجد البنا')
                                          : 'سجّل دخولك لتصبح عضواً في منصة د. ماجد البنا',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () => isLoggedIn
                                    ? _signOut(context)
                                    : _signInWithGoogle(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF6B4200),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(17),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (!isLoggedIn) ...[
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: const Color(0xFFE0E0E0),
                                          ),
                                        ),
                                        child: const Center(
                                          child: Text(
                                            'G',
                                            style: TextStyle(
                                              color: Color(0xFF4285F4),
                                              fontSize: 15,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                    ] else ...[
                                      const Icon(Icons.logout_rounded, size: 20),
                                      const SizedBox(width: 8),
                                    ],
                                    Text(
                                      isLoggedIn
                                          ? 'تسجيل الخروج'
                                          : 'تسجيل الدخول بواسطة Google',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // ── مظهر التطبيق ──
              AppSettingsCard(
                isDark: isDark,
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: gold.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isDark
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        color: gold,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('مظهر التطبيق',
                              style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                          const SizedBox(height: 3),
                          Text(
                            isDark ? 'الوضع الداكن مفعّل' : 'الوضع الفاتح مفعّل',
                            style: TextStyle(color: textSub, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => onThemeToggle(!isDark),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        width: 54,
                        height: 30,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          color: isDark ? gold : Colors.grey.shade300,
                          boxShadow: isDark
                              ? [
                                  BoxShadow(
                                    color: gold.withOpacity(0.4),
                                    blurRadius: 10,
                                  )
                                ]
                              : [],
                        ),
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          alignment: isDark
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: Container(
                            margin: const EdgeInsets.all(3),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 6,
                                )
                              ],
                            ),
                            child: Icon(
                              isDark
                                  ? Icons.dark_mode_rounded
                                  : Icons.light_mode_rounded,
                              size: 14,
                              color: isDark ? gold : Colors.orange,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── عن التطبيق ──
              AppSettingsCard(
                isDark: isDark,
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: gold.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.info_outline_rounded,
                          color: gold, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('عن التطبيق',
                              style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                          const SizedBox(height: 3),
                          Text('الإصدار ١.٠.٠',
                              style: TextStyle(color: textSub, fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: gold.withOpacity(0.1),
                      ),
                      child: const Icon(Icons.arrow_back_ios_rounded,
                          color: gold, size: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── تواصل مع المكتب ──
              AppSettingsCard(
                isDark: isDark,
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: gold.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.phone_outlined,
                          color: gold, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('تواصل مع المكتب',
                              style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                          const SizedBox(height: 3),
                          Text('مكتب لمسات الهندسي',
                              style: TextStyle(color: textSub, fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: gold.withOpacity(0.1),
                      ),
                      child: const Icon(Icons.arrow_back_ios_rounded,
                          color: gold, size: 14),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}