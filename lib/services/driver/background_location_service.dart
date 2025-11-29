import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:logistics_toolkit/services/driver/background_task_handler.dart';

class BackgroundLocationService {
  static final _service = FlutterBackgroundService();
  static Future<void> initializeService() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        autoStart: false,
        isForegroundMode: true,
        onStart: onStart,
        notificationChannelId: 'location_channel',
        initialNotificationTitle: 'Tracking Service',
        initialNotificationContent: 'Initializing...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
      ),
    );
  }
  /// Start background service if not already running
  static Future<void> startService() async {
    if (!await _service.isRunning()) {
      await _service.startService();
    }
  }
  /// Stop background service
  static Future<void> stopService() async {
    _service.invoke("stopService");
  }
}