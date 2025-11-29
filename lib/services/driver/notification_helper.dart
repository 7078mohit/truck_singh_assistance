import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _notifier =
  FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static const int _id = 888;
  static const String _channelId = 'location_channel';
  static const String _channelName = 'Location Tracking';

  static Future<void> initialize() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);

    await _notifier.initialize(settings);
    _initialized = true;
  }

  static void updateNotification(String title, String content) {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Persistent notification for background tracking.',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
    );

    _notifier.show(
      _id,
      title,
      content,
      const NotificationDetails(android: androidDetails),
    );
  }
}