import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/notifications/real_time_notification_service.dart';
import 'location_tracking_manager.dart';
import 'shipment_monitor.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }
  await _runServiceLogic(service);
}

Future<void> _runServiceLogic(ServiceInstance service) async {
  LocationTrackingManager? locationTracker;
  ShipmentMonitor? shipmentMonitor;
  final notificationService = RealTimeNotificationService();
  service.on('stopService').listen((event) {
    locationTracker?.stop();
    shipmentMonitor?.stop();
    service.stopSelf();
  });

  try {
    final prefs = await SharedPreferences.getInstance();
    final supabaseUrl = prefs.getString('supabaseUrl');
    final supabaseAnonKey = prefs.getString('supabaseAnonKey');
    if (supabaseUrl == null || supabaseAnonKey == null) {
      throw Exception("Supabase credentials missing.");
    }
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    final client = Supabase.instance.client;
    await notificationService.initialize();
    Future.microtask(() {
      Timer.periodic(const Duration(minutes: 15), (timer) async {
        final userId = prefs.getString('current_user_id');
        if (userId != null) {
          await notificationService.checkForNewNotifications(userId: userId);
        }
      });
    });
    final user = await _awaitUserSession(client.auth);
    if (user == null) throw Exception("User not signed in.");

    final driver = await _fetchDriverProfile(client, user.id);
    if (driver == null) throw Exception("Driver profile not found.");

    final id = driver['custom_user_id'];

    locationTracker = LocationTrackingManager(
      serviceInstance: service,
      supabaseClient: client,
      userId: user.id,
      customUserId: id,
    )..start();

    shipmentMonitor = ShipmentMonitor(
      supabaseClient: client,
      customUserId: id,
      onShipmentUpdate: locationTracker.setActiveShipment,
    )..start();
  } catch (e) {
    print("❌ Background startup error: $e");
    service.stopSelf();
  }
}

Future<User?> _awaitUserSession(GoTrueClient auth) async {
  if (auth.currentUser != null) return auth.currentUser;
  final completer = Completer<User?>();
  final sub = auth.onAuthStateChange.listen((event) {
    if (event.event == AuthChangeEvent.signedIn &&
        event.session?.user != null) {
      if (!completer.isCompleted) completer.complete(event.session!.user);
    }
  });

  await Future.delayed(const Duration(seconds: 15));
  if (!completer.isCompleted) completer.complete(auth.currentUser);

  final result = await completer.future;
  await sub.cancel();

  return result;
}

Future<Map<String, dynamic>?> _fetchDriverProfile(
    SupabaseClient client,
    String userId,
    ) async {
  try {
    return await client
        .from('user_profiles')
        .select('custom_user_id, truck_owner_id')
        .eq('user_id', userId)
        .single();
  } catch (_) {
    return null;
  }
}