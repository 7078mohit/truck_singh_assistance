import 'package:supabase_flutter/supabase_flutter.dart';

class DriverService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getActiveShipmentsForDriver(
      String? driverId,
      ) async {
    if (driverId == null) {
      throw Exception('Driver not authenticated or custom_user_id is missing.');
    }
    final activeStatuses = [
      'Accepted',
      'En Route to Pickup',
      'Arrived at Pickup',
      'In Transit',
    ];

    final response = await _client
        .from('shipment')
        .select('shipment_id, pickup, drop, assigned_agent')
        .eq('assigned_driver', driverId)
        .inFilter('booking_status', activeStatuses)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getAssociatedOwners(
      String? driverId,
      ) async {
    if (driverId == null) {
      throw Exception('Driver not authenticated or custom_user_id is missing.');
    }

    final relationResponse = await _client
        .from('driver_relation')
        .select('owner_custom_id')
        .eq('driver_custom_id', driverId);

    final ownerIds = relationResponse
        .map((row) => row['owner_custom_id'] as String)
        .where((id) => id.isNotEmpty)
        .toList();

    if (ownerIds.isEmpty) return [];
    final owners = await _client
        .from('user_profiles')
        .select('name, custom_user_id')
        .inFilter('custom_user_id', ownerIds);

    return List<Map<String, dynamic>>.from(owners);
  }
}