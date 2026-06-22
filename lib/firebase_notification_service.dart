import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  debugPrint('FCM Background Message: ${message.messageId}');
}

class FirebaseNotificationService {
  FirebaseNotificationService._();

  static bool _initialized = false;

  static const String generalNotificationsKey = 'general';
  static const String postsNotificationsKey = 'posts';
  static const String engineeringFilesNotificationsKey = 'engineering_files';
  static const String structuralPlansNotificationsKey = 'structural_plans';
  static const String lecturesNotificationsKey = 'lectures';

  static const List<String> notificationPreferenceKeys = [
    generalNotificationsKey,
    postsNotificationsKey,
    engineeringFilesNotificationsKey,
    structuralPlansNotificationsKey,
    lecturesNotificationsKey,
  ];

  static const Map<String, String> notificationTitles = {
    generalNotificationsKey: 'كل الإشعارات',
    postsNotificationsKey: 'إشعارات المنشورات',
    engineeringFilesNotificationsKey: 'إشعارات الملفات الهندسية',
    structuralPlansNotificationsKey: 'إشعارات المخططات الإنشائية',
    lecturesNotificationsKey: 'إشعارات المحاضرات',
  };

  static const Map<String, List<String>> _topicsByPreferenceKey = {
    postsNotificationsKey: ['posts'],
    engineeringFilesNotificationsKey: ['engineering_files', 'files', 'pdf_files'],
    structuralPlansNotificationsKey: ['structural_plans'],
    lecturesNotificationsKey: ['lectures', 'courses', 'schedule'],
  };

  static const String _prefsPrefix = 'notification_pref_';
  static const MethodChannel _settingsChannel =
      MethodChannel('majidalbana/notification_settings');

  static final StreamController<Map<String, dynamic>>
      _notificationClickController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get notificationClicks =>
      _notificationClickController.stream;

  static Map<String, dynamic>? _initialNotificationData;

  static Map<String, dynamic>? consumeInitialNotificationData() {
    final data = _initialNotificationData;
    _initialNotificationData = null;
    return data;
  }

  static void _handleNotificationClick(Map<String, dynamic> data) {
    debugPrint('Notification click data: $data');
    _notificationClickController.add(data);
  }

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'majidalbana_general_channel',
    'إشعارات تطبيق ماجد البنا',
    description: 'إشعارات المنشورات والملفات والمخططات والمحاضرات',
    importance: Importance.high,
  );

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await _requestPermission();
      await _setupLocalNotifications();
      await applySavedNotificationSubscriptions();
      await _printFcmToken();
      _listenToForegroundMessages();
      await _listenToNotificationClicks();
    } catch (e) {
      debugPrint('FirebaseNotificationService initialize error: $e');
    }
  }

  static Future<NotificationSettings?> _requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('Notification permission: ${settings.authorizationStatus}');
      return settings;
    } catch (e) {
      debugPrint('Notification permission request skipped/error: $e');
      return null;
    }
  }

  static Future<bool> requestNotificationPermission() async {
    final settings = await _requestPermission();
    if (settings == null) return await areSystemNotificationsEnabled();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  static Future<bool> areSystemNotificationsEnabled() async {
    try {
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final androidEnabled = await androidPlugin?.areNotificationsEnabled();
      if (androidEnabled != null) return androidEnabled;
    } catch (e) {
      debugPrint('Android notification permission check error: $e');
    }

    try {
      final settings = await _messaging.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('Notification settings check error: $e');
      return true;
    }
  }

  static Future<bool> openSystemNotificationSettings() async {
    try {
      final opened = await _settingsChannel.invokeMethod<bool>(
        'openNotificationSettings',
      );
      return opened == true;
    } catch (e) {
      debugPrint('Open notification settings channel error: $e');
      return false;
    }
  }

  static Future<Map<String, bool>> loadNotificationPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, bool>{};

    for (final key in notificationPreferenceKeys) {
      values[key] = prefs.getBool('$_prefsPrefix$key') ?? true;
    }

    return values;
  }

  static Future<void> setNotificationPreference(String key, bool enabled) async {
    if (!notificationPreferenceKeys.contains(key)) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefsPrefix$key', enabled);

    if (key == generalNotificationsKey && !enabled) {
      await _unsubscribeFromAllTopics();
      await _localNotifications.cancelAll();
      return;
    }

    if (key == generalNotificationsKey && enabled) {
      await requestNotificationPermission();
    }

    await applySavedNotificationSubscriptions();
  }

  static Future<void> applySavedNotificationSubscriptions() async {
    final values = await loadNotificationPreferences();
    final generalEnabled = values[generalNotificationsKey] ?? true;

    if (!generalEnabled) {
      await _unsubscribeFromAllTopics();
      return;
    }

    for (final entry in _topicsByPreferenceKey.entries) {
      final enabled = values[entry.key] ?? true;
      for (final topic in entry.value) {
        if (enabled) {
          await _subscribeToTopic(topic);
        } else {
          await _unsubscribeFromTopic(topic);
        }
      }
    }
  }

  static Future<void> _setupLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    const initSettings = InitializationSettings(
      android: androidInit,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Local notification clicked: ${response.payload}');

        final payload = response.payload;
        if (payload == null || payload.trim().isEmpty) {
          _handleNotificationClick({'screen': 'posts'});
          return;
        }

        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            _handleNotificationClick(Map<String, dynamic>.from(decoded));
          } else {
            _handleNotificationClick({'screen': 'posts'});
          }
        } catch (_) {
          _handleNotificationClick({'screen': 'posts'});
        }
      },
    );

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(_androidChannel);
  }

  static Future<void> _subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      debugPrint('Subscribed to FCM topic: $topic');
    } catch (e) {
      debugPrint('Subscribe to $topic topic error: $e');
    }
  }

  static Future<void> _unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      debugPrint('Unsubscribed from FCM topic: $topic');
    } catch (e) {
      debugPrint('Unsubscribe from $topic topic error: $e');
    }
  }

  static Future<void> _unsubscribeFromAllTopics() async {
    for (final topics in _topicsByPreferenceKey.values) {
      for (final topic in topics) {
        await _unsubscribeFromTopic(topic);
      }
    }
  }

  static Future<bool> _canShowForegroundMessage(RemoteMessage message) async {
    final values = await loadNotificationPreferences();
    if (values[generalNotificationsKey] == false) return false;

    final key = _preferenceKeyForMessage(message.data);
    if (key == null) return true;

    return values[key] ?? true;
  }

  static String? _preferenceKeyForMessage(Map<String, dynamic> data) {
    final raw = [
      data['notification_group'],
      data['notificationGroup'],
      data['topic'],
      data['category'],
      data['screen'],
      data['type'],
      data['section'],
    ].whereType<Object>().map((e) => e.toString().toLowerCase()).join(' ');

    if (raw.contains('post') || raw.contains('publication') || raw.contains('منشور')) {
      return postsNotificationsKey;
    }

    if (raw.contains('structural') ||
        raw.contains('plan') ||
        raw.contains('scheme') ||
        raw.contains('مخطط') ||
        raw.contains('انش') ||
        raw.contains('إنش')) {
      return structuralPlansNotificationsKey;
    }

    if (raw.contains('lecture') ||
        raw.contains('course') ||
        raw.contains('schedule') ||
        raw.contains('محاض') ||
        raw.contains('دور')) {
      return lecturesNotificationsKey;
    }

    if (raw.contains('file') || raw.contains('pdf') || raw.contains('ملف')) {
      return engineeringFilesNotificationsKey;
    }

    return null;
  }

  static Future<void> _printFcmToken() async {
    try {
      final token = await _messaging.getToken();
      debugPrint('FCM TOKEN: $token');

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        debugPrint('FCM TOKEN REFRESHED: $newToken');
        await applySavedNotificationSubscriptions();
      });
    } catch (e) {
      debugPrint('FCM token error: $e');
    }
  }

  static void _listenToForegroundMessages() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('FCM Foreground Message: ${message.messageId}');
      debugPrint('FCM Data: ${message.data}');

      if (!await _canShowForegroundMessage(message)) {
        debugPrint('Foreground notification muted by user preferences.');
        return;
      }

      final notification = message.notification;
      final android = message.notification?.android;

      if (notification == null || android == null) return;

      final androidDetails = await _buildAndroidNotificationDetails(
        title: notification.title,
        body: notification.body,
        imageUrl: message.data['image_url']?.toString(),
      );

      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(android: androidDetails),
        payload: jsonEncode(message.data),
      );
    });
  }

  static Future<AndroidNotificationDetails> _buildAndroidNotificationDetails({
    String? title,
    String? body,
    String? imageUrl,
  }) async {
    StyleInformation? styleInformation;

    final imageBytes = await _downloadNotificationImage(imageUrl);

    if (imageBytes != null) {
      styleInformation = BigPictureStyleInformation(
        ByteArrayAndroidBitmap(imageBytes),
        contentTitle: title,
        summaryText: body,
        hideExpandedLargeIcon: true,
      );
    }

    return AndroidNotificationDetails(
      _androidChannel.id,
      _androidChannel.name,
      channelDescription: _androidChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      styleInformation: styleInformation,
    );
  }

  static Future<Uint8List?> _downloadNotificationImage(String? imageUrl) async {
    if (imageUrl == null || imageUrl.trim().isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(imageUrl.trim());

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      debugPrint('Invalid notification image url: $imageUrl');
      return null;
    }

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 6));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }

      debugPrint(
        'Notification image download failed. HTTP: ${response.statusCode}',
      );
    } catch (e) {
      debugPrint('Notification image download error: $e');
    }

    return null;
  }

  static Future<void> _listenToNotificationClicks() async {
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notification opened from background');
      debugPrint('Message data: ${message.data}');

      _handleNotificationClick(message.data);
    });

    final initialMessage = await _messaging.getInitialMessage();

    if (initialMessage != null) {
      debugPrint('Notification opened from terminated state');
      debugPrint('Initial message data: ${initialMessage.data}');

      _initialNotificationData = initialMessage.data;
    }
  }
}
