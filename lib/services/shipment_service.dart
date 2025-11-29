import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/user_data_service.dart';

class ShipmentService {
  ShipmentService._();

  static final SupabaseClient _client = Supabase.instance.client;
  /// Fetch all marketplace shipments that are still pending
  static Future<List<Map<String, dynamic>>>
  getAvailableMarketplaceShipments() async {
    try {
      final response = await _client
          .from('shipment')
          .select('*, shipper:user_profiles!fk_shipper_custom_id(name)')
          .eq('booking_status', 'Pending');

      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      print("❌ Error fetching marketplace shipments: $error");
      rethrow;
    }
  }

  /// Accept a marketplace shipment and assign the current agent to it
  static Future<void> acceptMarketplaceShipment({
    required String shipmentId,
  }) async {
    try {
      final companyId = await UserDataService.getCustomUserId();
      if (companyId == null) throw Exception("🚫 No valid company ID found.");

      await _client
          .from('shipment')
          .update({'booking_status': 'Accepted', 'assigned_agent': companyId})
          .eq('shipment_id', shipmentId);
    } catch (error) {
      print("❌ Error accepting shipment: $error");
      rethrow;
    }
  }
  /// Get all shipments assigned to current agent
  static Future<List<Map<String, dynamic>>> getAllMyShipments() async {
    try {
      UserDataService.clearCache();
      final customUserId = await UserDataService.getCustomUserId();
      if (customUserId == null) throw Exception("🚫 User has no custom ID.");

      final response = await _client
          .from('shipment')
          .select('*, shipper:user_profiles!fk_shipper_custom_id(name)')
          .eq('assigned_agent', customUserId);

      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      print("❌ Error fetching assigned shipments: $error");
      rethrow;
    }
  }

  /// Get shipments by status (with optional search)
  static Future<List<Map<String, dynamic>>> getShipmentsByStatus({
    required List<String> statuses,
    String? searchQuery,
  }) async {
    try {
      var query = _client
          .from('shipment')
          .select()
          .inFilter('booking_status', statuses);

      if (searchQuery?.isNotEmpty == true) {
        final q = searchQuery!.toLowerCase();
        query = query.or(
          'shipment_id.ilike.%$q%,pickup.ilike.%$q%,drop.ilike.%$q%',
        );
      }
      final response = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      print("❌ Error filtering shipments: $error");
      throw Exception('Failed to fetch shipments by status.');
    }
  }

  /// Get completed shipments for logged-in agent
  static Future<List<Map<String, dynamic>>> getAllMyCompletedShipments() async {
    try {
      final customUserId = await UserDataService.getCustomUserId();
      if (customUserId == null) throw Exception("🚫 Missing custom ID.");

      final response = await _client
          .from('shipment')
          .select('*, shipper:user_profiles!fk_shipper_custom_id(name)')
          .eq('assigned_agent', customUserId)
          .eq('booking_status', 'Completed');

      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      print("❌ Error fetching completed shipments: $error");
      rethrow;
    }
  }

  /// Assign a truck to shipment
  static Future<void> assignTruck({
    required String shipmentId,
    required String truckNumber,
  }) async {
    try {
      await _client
          .from('shipment')
          .update({'assigned_truck': truckNumber})
          .eq('shipment_id', shipmentId);
    } catch (error) {
      print("❌ Error assigning truck: $error");
      rethrow;
    }
  }
  /// Assign a driver to shipment
  static Future<void> assignDriver({
    required String shipmentId,
    required String driverUserId,
  }) async {
    try {
      await _client
          .from('shipment')
          .update({'assigned_driver': driverUserId})
          .eq('shipment_id', shipmentId);
    } catch (error) {
      print("❌ Error assigning driver: $error");
      rethrow;
    }
  }
  /// Generic status update
  static Future<void> updateStatus(String shipmentId, String newStatus) async {
    try {
      await _client
          .from('shipment')
          .update({'booking_status': newStatus})
          .eq('shipment_id', shipmentId);
    } catch (error) {
      print("❌ Error updating status: $error");
      rethrow;
    }
  }
}