import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

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
    'majidalbana_posts_channel',
    'إشعارات المنشورات',
    description: 'إشعارات عند نشر منشور جديد في التطبيق',
    importance: Importance.high,
  );

static Future<void> initialize() async {
  if (_initialized) return;
  _initialized = true;

  try {
    await _requestPermission();
    await _setupLocalNotifications();
    await _subscribeToPostsTopic();
await _printFcmToken();
_listenToForegroundMessages();
await _listenToNotificationClicks();
  } catch (e) {
    debugPrint('FirebaseNotificationService initialize error: $e');
  }
}

static Future<void> _requestPermission() async {
  try {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('Notification permission: ${settings.authorizationStatus}');
  } catch (e) {
    debugPrint('Notification permission request skipped/error: $e');
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
static Future<void> _subscribeToPostsTopic() async {
  try {
    await _messaging.subscribeToTopic('posts');
    debugPrint('Subscribed to FCM topic: posts');
  } catch (e) {
    debugPrint('Subscribe to posts topic error: $e');
  }
}
  static Future<void> _printFcmToken() async {
    try {
      final token = await _messaging.getToken();
      debugPrint('FCM TOKEN: $token');

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        debugPrint('FCM TOKEN REFRESHED: $newToken');
      });
    } catch (e) {
      debugPrint('FCM token error: $e');
    }
  }

  static void _listenToForegroundMessages() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('FCM Foreground Message: ${message.messageId}');
      debugPrint('FCM Data: ${message.data}');

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