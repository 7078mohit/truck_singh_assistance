import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class NotificationManager {
  static final NotificationManager _instance = NotificationManager._internal();
  factory NotificationManager() => _instance;
  NotificationManager._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<String?> createNotification({
    required String userId,
    required String title,
    required String message,
    String type = 'general',
    String sourceType = 'app',
    String? sourceId,
  }) async {
    try {
      final result = await _supabase.rpc(
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
        debugPrint('✅ Notification created for $userId: "$title"');
      }
      return result as String?;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error creating notification: $e');
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
    String message;
    switch (status.toLowerCase()) {
      case 'accepted':
        message = 'Shipment $shipmentId is now accepted and ready for pickup.';
        break;
      case 'in transit':
        message =
        'Shipment $shipmentId is in transit from ${pickup ?? 'origin'} to ${drop ?? 'destination'}.';
        break;
      case 'delivered':
        message =
        'Shipment $shipmentId has been delivered to ${drop ?? 'destination'}.';
        break;
      case 'cancelled':
        message = 'Shipment $shipmentId has been cancelled.';
        break;
      default:
        message = 'Shipment $shipmentId status updated to $status.';
    }

    await createNotification(
      userId: userId,
      title: 'Shipment Status Updated',
      message: message,
      type: 'shipment',
      sourceType: 'app',
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
      title: 'Complaint Filed Successfully',
      message:
      'Your complaint regarding "$complaintSubject" has been submitted.',
      type: 'complaint',
      sourceId: complaintId,
    );

    if (targetUserId != null) {
      await createNotification(
        userId: targetUserId,
        title: 'A Complaint Has Been Filed',
        message:
        'A complaint regarding "$complaintSubject" has been filed against you.',
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
    String message;
    switch (status.toLowerCase()) {
      case 'resolved':
        message =
        'Your complaint regarding "$complaintSubject" has been marked resolved.';
        break;
      case 'rejected':
        message =
        'Your complaint regarding "$complaintSubject" has been rejected.';
        break;
      default:
        message =
        'Complaint "$complaintSubject" status updated to $status.';
    }

    await createNotification(
      userId: userId,
      title: 'Complaint Status Updated',
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