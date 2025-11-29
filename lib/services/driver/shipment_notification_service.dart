import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../notification_manager.dart';
import '../../main.dart';

class ShipmentNotificationService {
  static final ShipmentNotificationService _instance =
  ShipmentNotificationService._internal();
  factory ShipmentNotificationService() => _instance;
  ShipmentNotificationService._internal();

  final NotificationManager _notificationManager = NotificationManager();
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> updateShipmentStatus({
    required String shipmentId,
    required String newStatus,
    String? notes,
    String? location,
  }) async {
    try {
      final shipment = await _supabase
          .from('shipment')
          .select('shipper_id, assigned_driver, assigned_agent, pickup, drop')
          .eq('shipment_id', shipmentId)
          .single();
      await _supabase
          .from('shipment')
          .update({'booking_status': newStatus})
          .eq('shipment_id', shipmentId);

      debugPrint(
        "📦 Updating: shipment=$shipmentId, driver=${shipment['assigned_driver']}",
      );

      await _supabase.from('shipment_updates').insert({
        'shipment_id': shipmentId,
        'status': newStatus,
        'notes': notes ?? 'Status updated to $newStatus',
        'location': location,
        'timestamp': DateTime.now().toIso8601String(),
        'assigned_driver': shipment['assigned_driver'],
        'updated_by_user_id': supabase.auth.currentUser?.id,
      });
      await _createShipmentStatusNotifications(shipment, newStatus, shipmentId);

      debugPrint('✅ Shipment updated: $shipmentId → $newStatus');
    } catch (e) {
      debugPrint('❌ Failed updating shipment status: $e');
      rethrow;
    }
  }

  Future<void> _createShipmentStatusNotifications(
      Map<String, dynamic> shipment,
      String newStatus,
      String shipmentId,
      ) async {
    try {
      final pickup = shipment['pickup'] ?? 'origin';
      final drop = shipment['drop'] ?? 'destination';

      final customUserIds = <String>[
        if (shipment['shipper_id'] != null) shipment['shipper_id'],
        if (shipment['assigned_driver'] != null) shipment['assigned_driver'],
        if (shipment['assigned_agent'] != null) shipment['assigned_agent'],
      ];

      if (customUserIds.isEmpty) return;
      final profiles = await _supabase
          .from('user_profiles')
          .select('user_id')
          .inFilter('custom_user_id', customUserIds);
      for (final profile in profiles) {
        final userId = profile['user_id'];
        if (userId != null) {
          await _notificationManager.createShipmentNotification(
            userId: userId,
            shipmentId: shipmentId,
            status: newStatus,
            pickup: pickup,
            drop: drop,
          );
        }
      }
      debugPrint(
        '🔔 Notifications sent to ${profiles.length} users (shipment: $shipmentId)',
      );
    } catch (e) {
      debugPrint('❌ Failed creating notifications: $e');
    }
  }

  Future<void> assignDriverToShipment({
    required String shipmentId,
    required String driverCustomId,
  }) async {
    try {
      await _supabase
          .from('shipment')
          .update({'assigned_driver': driverCustomId})
          .eq('shipment_id', shipmentId);

      final shipment = await _supabase
          .from('shipment')
          .select('assigned_agent, pickup, drop')
          .eq('shipment_id', shipmentId)
          .single();

      await _createDriverAssignmentNotifications(
        shipment,
        driverCustomId,
        shipmentId,
      );

      debugPrint('🚚 Assigned driver=$driverCustomId → shipment=$shipmentId');
    } catch (e) {
      debugPrint('❌ Failed assigning driver: $e');
      rethrow;
    }
  }

  Future<void> _createDriverAssignmentNotifications(
      Map<String, dynamic> shipment,
      String driverCustomId,
      String shipmentId,
      ) async {
    try {
      final pickup = shipment['pickup'] ?? 'origin';
      final drop = shipment['drop'] ?? 'destination';

      final profiles = await _supabase
          .from('user_profiles')
          .select('user_id, name, custom_user_id')
          .inFilter('custom_user_id', [
        driverCustomId,
        shipment['assigned_agent'],
      ]);

      String driverName = driverCustomId;

      final driverProfile = profiles.firstWhere(
            (p) => p['custom_user_id'] == driverCustomId,
        orElse: () => const {},
      );
      if (driverProfile.isNotEmpty) {
        driverName = driverProfile['name'] ?? driverCustomId;
        await _notificationManager.createNotification(
          userId: driverProfile['user_id'],
          title: 'New Shipment Assigned',
          message:
          'You have been assigned shipment $shipmentId from $pickup → $drop.',
          type: 'shipment',
          sourceId: shipmentId,
        );
      }

      final agentProfile = profiles.firstWhere(
            (p) => p['custom_user_id'] == shipment['assigned_agent'],
        orElse: () => const {},
      );
      if (agentProfile.isNotEmpty) {
        await _notificationManager.createNotification(
          userId: agentProfile['user_id'],
          title: 'Driver Assigned',
          message: 'Driver $driverName is assigned to shipment $shipmentId.',
          type: 'shipment',
          sourceId: shipmentId,
        );
      }
    } catch (e) {
      debugPrint('❌ Error creating notifications: $e');
    }
  }
}