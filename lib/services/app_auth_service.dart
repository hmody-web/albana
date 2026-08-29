import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'apple_profile_service.dart';

/// Centralized authentication helpers used throughout the app.
class AppAuthService {
  AppAuthService._();

  static bool get showAppleSignIn =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool isAppleUser(User? user) {
    if (user == null) return false;
    return user.providerData.any((provider) => provider.providerId == 'apple.com');
  }

  static String userIdentity(User user) {
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) return email;
    // Stable fallback for Apple accounts that did not expose an email.
    return 'apple.${user.uid}@users.majidalbana.local';
  }

  static String displayNameFor(User? user) {
    if (user == null) return 'مستخدم';
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final providerName = user.providerData
        .map((p) => p.displayName?.trim())
        .whereType<String>()
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (providerName.isNotEmpty) return providerName;
    final email = user.email?.trim() ?? '';
    if (email.isNotEmpty && !email.endsWith('@privaterelay.appleid.com')) {
      final local = email.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ').trim();
      if (local.isNotEmpty) return local;
    }
    return 'مستخدم';
  }

  static Future<UserCredential?> signInWithGoogle({BuildContext? context}) async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final result = await FirebaseAuth.instance.signInWithCredential(credential);
    await result.user?.reload();
    final user = FirebaseAuth.instance.currentUser ?? result.user;
    if (user != null && context != null && context.mounted && result.additionalUserInfo?.isNewUser == true) {
      final completed = await AppleProfileService.ensureProfile(
        context,
        user,
        forceEdit: true,
        requireConfirmation: true,
      );
      if (!completed) {
        await FirebaseAuth.instance.signOut();
        return null;
      }
    }
    return result;
  }


  static bool isCancelledError(Object error) {
    if (error is SignInWithAppleAuthorizationException) {
      return error.code == AuthorizationErrorCode.canceled;
    }
    if (error is FirebaseAuthException) {
      const cancelledCodes = {
        'web-context-cancelled',
        'canceled',
        'cancelled',
        'user-cancelled',
      };
      return cancelledCodes.contains(error.code.toLowerCase());
    }
    final text = error.toString().toLowerCase();
    return text.contains('authorizationerrorcode.canceled') ||
        text.contains('cancelled') ||
        text.contains('canceled by user');
  }

  static Future<UserCredential?> signInWithApple({BuildContext? context}) async {
    if (!showAppleSignIn) {
      throw UnsupportedError('تسجيل الدخول بواسطة Apple متاح على أجهزة iOS فقط.');
    }

    try {
      // استخدم مسار Firebase الأصلي على iOS. هذا يتجنب فشل تبديل Apple ID token
      // الذي كان يظهر أحياناً كخطأ شبكة رغم أن اتصال الجهاز سليم.
      final provider = AppleAuthProvider();
      final result = await FirebaseAuth.instance.signInWithProvider(provider);

      final user = result.user;
      if (user != null) {
        await user.reload();
        if (context != null && context.mounted) {
          final current = FirebaseAuth.instance.currentUser ?? user;
          final completed = await AppleProfileService.ensureProfile(context, current);
          if (!completed) {
            await FirebaseAuth.instance.signOut();
            return null;
          }
        }
      }

      return result;
    } catch (e) {
      if (isCancelledError(e)) return null;
      rethrow;
    }
  }

  static Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
  }

  /// Re-authenticates the current user before destructive account deletion.
  /// For Apple, the returned authorization code is later used to revoke the
  /// Sign in with Apple token as required by Apple before deleting Firebase Auth.
  static Future<String?> reauthenticateForAccountDeletion(User user) async {
    if (isAppleUser(user)) {
      final result = await user.reauthenticateWithProvider(AppleAuthProvider());
      final authorizationCode = result.additionalUserInfo?.authorizationCode;
      if (authorizationCode == null || authorizationCode.isEmpty) {
        throw Exception('تعذر تأكيد حساب Apple للحذف. حاول مرة أخرى.');
      }
      return authorizationCode;
    }

    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      throw Exception('يجب تسجيل الدخول مرة أخرى بواسطة Google لتأكيد حذف الحساب.');
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    await user.reauthenticateWithCredential(credential);
    return null;
  }

  /// Deletes the already re-authenticated Firebase account.
  /// Apple accounts also have their Apple authorization token revoked first.
  static Future<void> deleteReauthenticatedAccount({String? appleAuthorizationCode}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (isAppleUser(user)) {
      final code = appleAuthorizationCode?.trim() ?? '';
      if (code.isEmpty) {
        throw Exception('رمز تأكيد Apple غير متوفر لإكمال حذف الحساب.');
      }
      await FirebaseAuth.instance.revokeTokenWithAuthorizationCode(code);
    }

    await user.delete();
  }

  static Future<void> reauthenticateAndDelete(User user) async {
    final authorizationCode = await reauthenticateForAccountDeletion(user);
    await deleteReauthenticatedAccount(appleAuthorizationCode: authorizationCode);
  }
}
