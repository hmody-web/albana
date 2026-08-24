import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_auth_service.dart';

class PlatformUserService {
  PlatformUserService._();
  static const _base = 'https://majidalbana.com/admin/users/client.php';
  static const _prefsKey = 'platform_supervisors';
  static const _deviceIdKey = 'platform_device_id_v1';
  static final Set<String> _supervisors = <String>{
    'hmode.qq@gmail.com','hmode.qu@gmail.com','info@majidalbana.com'
  };
  static bool currentUserBannedFromComments = false;
  static final ValueNotifier<bool> bannedCommentsNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<int> supervisorRevisionNotifier = ValueNotifier<int>(0);
  static Timer? _statusTimer;
  static Map<String,String>? _devicePayloadCache;

  static bool isSupervisorEmail(String? email) =>
      email != null && _supervisors.contains(email.trim().toLowerCase());


  static String _iosMarketingModel(String machine, String fallback) {
    const models = <String, String>{
      'iPhone11,2':'iPhone XS','iPhone11,4':'iPhone XS Max','iPhone11,6':'iPhone XS Max','iPhone11,8':'iPhone XR',
      'iPhone12,1':'iPhone 11','iPhone12,3':'iPhone 11 Pro','iPhone12,5':'iPhone 11 Pro Max','iPhone12,8':'iPhone SE (2nd generation)',
      'iPhone13,1':'iPhone 12 mini','iPhone13,2':'iPhone 12','iPhone13,3':'iPhone 12 Pro','iPhone13,4':'iPhone 12 Pro Max',
      'iPhone14,2':'iPhone 13 Pro','iPhone14,3':'iPhone 13 Pro Max','iPhone14,4':'iPhone 13 mini','iPhone14,5':'iPhone 13','iPhone14,6':'iPhone SE (3rd generation)',
      'iPhone14,7':'iPhone 14','iPhone14,8':'iPhone 14 Plus','iPhone15,2':'iPhone 14 Pro','iPhone15,3':'iPhone 14 Pro Max',
      'iPhone15,4':'iPhone 15','iPhone15,5':'iPhone 15 Plus','iPhone16,1':'iPhone 15 Pro','iPhone16,2':'iPhone 15 Pro Max',
      'iPhone17,1':'iPhone 16 Pro','iPhone17,2':'iPhone 16 Pro Max','iPhone17,3':'iPhone 16','iPhone17,4':'iPhone 16 Plus','iPhone17,5':'iPhone 16e',
    };
    return models[machine] ?? (fallback.trim().isNotEmpty ? fallback.trim() : 'iPhone');
  }

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList(_prefsKey) ?? const <String>[];
      _supervisors.addAll(cached.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty));
    } catch (_) {}
    await refreshSupervisors();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) await syncUser(user);
    _startStatusPolling();
  }

  static Future<void> refreshSupervisors() async {
    try {
      final r = await http.get(Uri.parse('$_base?action=supervisors')).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map && d['supervisors'] is List) {
        final values = (d['supervisors'] as List).map((e) => '$e'.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet();
        if (!setEquals(_supervisors, values)) {
          _supervisors..clear()..addAll(values);
          supervisorRevisionNotifier.value++;
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_prefsKey, values.toList());
      }
    } catch (_) {}
  }

  static Future<Map<String,String>> _devicePayload() async {
    if (_devicePayloadCache != null) return Map<String,String>.from(_devicePayloadCache!);
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceIdKey) ?? '';
    if (deviceId.isEmpty) {
      deviceId = '${DateTime.now().microsecondsSinceEpoch}_${Object().hashCode}_${Platform.operatingSystem}';
      await prefs.setString(_deviceIdKey, deviceId);
    }
    String platform = Platform.operatingSystem;
    String manufacturer = '';
    String model = '';
    String hardwareModel = '';
    String osVersion = Platform.operatingSystemVersion;
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        platform = 'android';
        manufacturer = a.manufacturer;
        model = a.model;
        hardwareModel = a.device;
        osVersion = 'Android ${a.version.release} (SDK ${a.version.sdkInt})';
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        platform = 'ios';
        manufacturer = 'Apple';
        hardwareModel = i.utsname.machine;
        model = _iosMarketingModel(hardwareModel, i.model);
        osVersion = '${i.systemName} ${i.systemVersion}';
      }
    } catch (_) {}
    String appVersion = '';
    String appBuild = '';
    try {
      final pkg = await PackageInfo.fromPlatform();
      appVersion = pkg.version;
      appBuild = pkg.buildNumber;
    } catch (_) {}
    final language = PlatformDispatcher.instance.locale.toLanguageTag();
    _devicePayloadCache = <String,String>{
      'device_id': deviceId,
      'source': 'app',
      'platform': platform,
      'manufacturer': manufacturer,
      'model': model,
      'hardware_model': hardwareModel,
      'os_version': osVersion,
      'app_version': appVersion,
      'app_build': appBuild,
      'language': language,
    };
    return Map<String,String>.from(_devicePayloadCache!);
  }

  static Future<void> syncUser(User user) async {
    try {
      final provider = user.providerData.any((p) => p.providerId == 'apple.com') ? 'apple' : 'google';
      final body = <String,String>{
        'action': 'sync',
        'email': AppAuthService.userIdentity(user),
        'name': AppAuthService.displayNameFor(user),
        'avatar': (user.photoURL ?? '').trim(),
        'uid': user.uid,
        'provider': provider,
        'source': 'app',
      };
      body.addAll(await _devicePayload());
      final r = await http.post(Uri.parse(_base), body: body).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final d = jsonDecode(utf8.decode(r.bodyBytes));
        if (d is Map) _setBanned(d['banned_comments'] == true || '${d['banned_comments']}' == '1');
      }
    } catch (_) {}
  }
  static void _setBanned(bool value) {
    currentUserBannedFromComments = value;
    if (bannedCommentsNotifier.value != value) bannedCommentsNotifier.value = value;
  }

  static void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await refreshCurrentUserStatus();
    });
  }

  static Future<bool> refreshCurrentUserStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _setBanned(false);
      return false;
    }
    try {
      final email = AppAuthService.userIdentity(user);
      final device = await _devicePayload();
      final uri = Uri.parse('$_base?action=status&email=${Uri.encodeQueryComponent(email)}');
      final r = await http.post(uri, headers: const {'Cache-Control': 'no-cache'}, body: <String,String>{
        'email': email,
        'name': AppAuthService.displayNameFor(user),
        'avatar': (user.photoURL ?? '').trim(),
        'uid': user.uid,
        'provider': user.providerData.any((p) => p.providerId == 'apple.com') ? 'apple' : 'google',
        ...device,
      }).timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        final d = jsonDecode(utf8.decode(r.bodyBytes));
        if (d is Map) {
          final value = d['banned_comments'] == true || '${d['banned_comments']}' == '1';
          _setBanned(value);
          final isSupervisor = d['is_supervisor'] == true || '${d['is_supervisor']}' == '1';
          final normalized = email.trim().toLowerCase();
          final hadSupervisor = _supervisors.contains(normalized);
          if (isSupervisor && !hadSupervisor) {
            _supervisors.add(normalized);
            supervisorRevisionNotifier.value++;
          } else if (!isSupervisor && hadSupervisor) {
            _supervisors.remove(normalized);
            supervisorRevisionNotifier.value++;
          }
          return value;
        }
      }
    } catch (_) {}
    return currentUserBannedFromComments;
  }
}
