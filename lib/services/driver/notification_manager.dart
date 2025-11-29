import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class NotificationManager {
  static final NotificationManager _instance = NotificationManager._();
  factory NotificationManager() => _instance;
  NotificationManager._();
  final SupabaseClient _db = Supabase.instance.client;

  Future<String?> createNotification({
    required String userId,
    required String title,
    required String message,
    String type = 'general',
    String sourceType = 'app',
    String? sourceId,
  }) async {
    try {
      final result = await _db.rpc(
        'create_smart_notification',
        params: {
          'p_user_id': userId,
          'p_title': title,
          'p_message': message,
          'p_type': type,
          'p_source_type': sourceType,
          'p_source_id': sourceId,
        },
      );

      if (kDebugMode) {
        debugPrint('🟢 Notification sent: $title --> $userId');
      }
      return result as String?;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('🔴 Notification Error: $e');
      }
      return null;
    }
  }

  Future<void> createShipmentNotification({
    required String userId,
    required String shipmentId,
    required String status,
    String? pickup,
    String? drop,
  }) async {
    final message = switch (status.toLowerCase()) {
      'accepted' => 'Shipment $shipmentId is accepted and ready for pickup.',
      'in transit' =>
      'Shipment $shipmentId is in transit from ${pickup ?? 'origin'} to ${drop ?? 'destination'}.',
      'delivered' =>
      'Shipment $shipmentId has been delivered to ${drop ?? 'destination'}.',
      'cancelled' => 'Shipment $shipmentId has been cancelled.',
      _ => 'Shipment $shipmentId status updated: $status.',
    };

    await createNotification(
      userId: userId,
      title: 'Shipment Updated',
      message: message,
      type: 'shipment',
      sourceId: shipmentId,
    );
  }

  Future<void> createComplaintFiledNotification({
    required String complainerId,
    required String complaintSubject,
    String? targetUserId,
    String? complaintId,
  }) async {
    await createNotification(
      userId: complainerId,
      title: 'Complaint Submitted',
      message: 'Your complaint "$complaintSubject" has been submitted.',
      type: 'complaint',
      sourceId: complaintId,
    );

    if (targetUserId case final id?) {
      await createNotification(
        userId: id,
        title: 'Complaint Filed',
        message: 'A complaint about "$complaintSubject" was filed against you.',
        type: 'complaint',
        sourceId: complaintId,
      );
    }
  }

  Future<void> createComplaintStatusNotification({
    required String userId,
    required String complaintSubject,
    required String status,
    String? complaintId,
  }) async {
    final message = switch (status.toLowerCase()) {
      'resolved' => 'Your complaint "$complaintSubject" is resolved.',
      'rejected' => 'Your complaint "$complaintSubject" was rejected.',
      _ => 'Complaint "$complaintSubject" updated to: $status.',
    };

    await createNotification(
      userId: userId,
      title: 'Complaint Updated',
      message: message,
      type: 'complaint',
      sourceId: complaintId,
    );
  }

  Future<void> createBulkNotification({
    required List<String> userIds,
    required String title,
    required String message,
    String type = 'bulk',
    String? sourceId,
  }) async {
    for (final userId in userIds) {
      await createNotification(
        userId: userId,
        title: title,
        message: message,
        type: type,
        sourceId: sourceId,
      );
    }
  }
}