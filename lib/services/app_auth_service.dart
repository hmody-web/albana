import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
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

  static String _randomNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  static String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();

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
      final rawNonce = _randomNonce();
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: _sha256(rawNonce),
      );

      final idToken = appleCredential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw FirebaseAuthException(
          code: 'missing-apple-id-token',
          message: 'Apple did not return an identity token.',
        );
      }

      final fullName = AppleFullPersonName(
        givenName: appleCredential.givenName,
        familyName: appleCredential.familyName,
      );
      final oauthCredential = AppleAuthProvider.credentialWithIDToken(
        idToken,
        rawNonce,
        fullName,
      );
      final result = await FirebaseAuth.instance.signInWithCredential(oauthCredential);

      final user = result.user;
      if (user != null) {
        final suppliedName = [appleCredential.givenName, appleCredential.familyName]
            .whereType<String>()
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .join(' ')
            .trim();

        final prefs = await SharedPreferences.getInstance();
        final nameKey = 'apple_display_name_${user.uid}';
        if (suppliedName.isNotEmpty && ((user.displayName ?? '').trim().isEmpty || (user.displayName ?? '').trim() == 'مستخدم')) {
          await prefs.setString(nameKey, suppliedName);
          await user.updateDisplayName(suppliedName);
        } else if ((user.displayName ?? '').trim().isEmpty) {
          final cachedName = prefs.getString(nameKey)?.trim() ?? '';
          if (cachedName.isNotEmpty) {
            await user.updateDisplayName(cachedName);
          }
        }
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
