import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Privacy-safe local notifications for incoming messages.
///
/// The notification NEVER contains message content — messages are end-to-end
/// encrypted, so plaintext stays inside the chat screen. We only show that a
/// new encrypted message arrived.
///
/// Note: these fire while the app process is alive (foreground or background).
/// True push notifications when the app is fully killed require FCM + a
/// server-side trigger — a deliberate next step (see BUILD.md).
class NotificationService {
  static const _channelId = 'nyvox_messages';
  static const _channelName = 'Messages';
  static const _channelDesc = 'Incoming encrypted messages';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: darwinInit),
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  Future<void> showMessageNotification() async {
    if (!_initialized) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Nyvox',
      '🔒 New encrypted message',
      details,
    );
  }
}

/// The app has exactly one notification service.
final notificationService = NotificationService();
