import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class ShipmentManager {
  ShipmentManager._();

  static final SupabaseClient _client = Supabase.instance.client;

  static Future<void> updateShipmentStatus(
      String shipmentId,
      String newStatus,
      ) async {
    try {
      await _client
          .from('shipment')
          .update({'booking_status': newStatus})
          .eq('shipment_id', shipmentId);

      debugPrint(
        "📦 Shipment `$shipmentId` updated → Status: `$newStatus`. Notification webhook triggered.",
      );
    } catch (error, stack) {
      debugPrint('❌ updateShipmentStatus failed: $error');
      debugPrint(stack.toString());
      rethrow;
    }
  }
}