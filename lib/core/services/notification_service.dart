import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants/app_strings.dart';

/// Must be a top-level (or static) function, and marked with this pragma,
/// so Android can find and run it in a separate isolate when the app is
/// fully killed and a push arrives. For plain "notification" messages
/// (which is all this app receives — see Worker) Android shows these via
/// the system tray automatically without any code even running; this
/// handler mainly matters if data-only messages are ever added later.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Intentionally minimal — do not touch UI/state here, this runs in an
  // isolate with no widget tree.
}

/// Real FCM push notifications — work even when the app is fully closed.
/// A backend Cloud Function (see /functions in the repo) watches the
/// `orders` node and sends a push whenever an order's status changes; this
/// service just registers this device's token and displays incoming pushes.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('Firebase init failed: $e');
      return;
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: androidInit));

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // Foreground pushes don't show automatically on Android — show them
    // ourselves via local notifications so it feels the same as background.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final n = message.notification;
      if (n != null) {
        show(id: message.hashCode, title: n.title ?? 'TezDrop', body: n.body ?? '');
      }
    });

    _ready = true;
  }

  /// Call after login (and again if the token refreshes) so the backend
  /// knows which device to push this customer's order updates to.
  static Future<void> saveTokenForPhone(String phone) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await http.patch(
        Uri.parse('${AppStrings.firebaseUrl}/users/${Uri.encodeComponent(phone)}.json'),
        body: jsonEncode({'fcmToken': token, 'phone': phone}),
      );
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        http.patch(
          Uri.parse('${AppStrings.firebaseUrl}/users/${Uri.encodeComponent(phone)}.json'),
          body: jsonEncode({'fcmToken': newToken}),
        );
      });
    } catch (e) {
      debugPrint('FCM token save failed: $e');
    }
  }

  static Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    const details = AndroidNotificationDetails(
      'tezdrop_orders',
      'Order Updates',
      channelDescription: 'Live updates about your TezDrop order status',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    await _plugin.show(id, title, body, const NotificationDetails(android: details));
  }

  // ── Trigger a real push to someone ELSE via the free Cloudflare Worker ──
  // (the Worker holds the Firebase service account key so this app never has to)
  static const _workerUrl = 'https://tezdrop-notify.tezdrop-apps.workers.dev/notify';
  static const _workerKey = 'UmomKaql0PE29yN8BShz_0oKQo0lAUx35bey5BxZfF0';

  static Future<void> notifyOthers({
    required String path,
    required String title,
    required String body,
  }) async {
    try {
      await http.post(
        Uri.parse(_workerUrl),
        headers: {'Content-Type': 'application/json', 'x-tezdrop-key': _workerKey},
        body: jsonEncode({'path': path, 'title': title, 'body': body}),
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Worker notify failed: $e');
    }
  }
}
