import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Centralized authentication helpers used throughout the app.
///
/// Apple Sign In is intentionally exposed only on iOS/iPadOS builds.
class AppAuthService {
  AppAuthService._();

  static bool get showAppleSignIn => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool isAppleUser(User? user) {
    if (user == null) return false;
    return user.providerData.any((provider) => provider.providerId == 'apple.com');
  }

  static Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final result = await FirebaseAuth.instance.signInWithCredential(credential);
    await result.user?.reload();
    return result;
  }

  static Future<UserCredential> signInWithApple() async {
    if (!showAppleSignIn) {
      throw UnsupportedError('تسجيل الدخول بواسطة Apple متاح على أجهزة iOS فقط.');
    }

    final provider = AppleAuthProvider();
    final result = await FirebaseAuth.instance.signInWithProvider(provider);
    await result.user?.reload();
    return result;
  }

  static Future<void> signOut() async {
    // Signing out of Google is safe even if the current Firebase user used Apple.
    // Keep Firebase and Google local sessions synchronized when Google was used.
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
  }

  /// Re-authenticates with the provider used by the account, then deletes it.
  /// For Apple, the fresh authorization code is also used to revoke the token,
  /// which is required for apps that offer account deletion.
  static Future<void> reauthenticateAndDelete(User user) async {
    if (isAppleUser(user)) {
      final result = await user.reauthenticateWithProvider(AppleAuthProvider());
      final authorizationCode = result.additionalUserInfo?.authorizationCode;
      if (authorizationCode != null && authorizationCode.isNotEmpty) {
        await FirebaseAuth.instance.revokeTokenWithAuthorizationCode(authorizationCode);
      }
      await FirebaseAuth.instance.currentUser?.delete();
      return;
    }

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
