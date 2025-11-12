import 'package:supabase_flutter/supabase_flutter.dart';

class MytripsServices {
  final _client = Supabase.instance.client;

  Future<Map<String, String?>> getUserProfile(String userId) async {
    final profile = await _client
        .from('user_profiles')
        .select('custom_user_id, role')
        .eq('user_id', userId)
        .maybeSingle();

    if (profile == null) return {};
    return {
      'custom_user_id': profile['custom_user_id'] as String?,
      'role': profile['role'] as String?,
    };
  }

  Future<List<Map<String, dynamic>>> getShipmentsForUser(String userId) async {
    final profile = await getUserProfile(userId);
    final customId = profile['custom_user_id'];
    final role = profile['role'];

    if (customId == null || role == null) {
      return [];
    }

    String column;
    switch (role) {
      case 'shipper':
        column = 'shipper_id';
        break;
      case 'truckowner':
        column = 'assigned_truckowner';
        break;
      case 'driver_individual':
        column = 'assigned_driver';
        break;
      case 'driver':
        column = 'assigned_driver';
        break;
      case 'driver_company':
        column = 'assigned_driver';
        break;
      case 'agent':
        column = 'assigned_agent';
        break;
      default:
        return [];
    }

    final response = await _client
        .from('shipment')
        .select()
        .eq(column, customId)
        .order('created_at');

    return List<Map<String, dynamic>>.from(response);
  }

  // --- existing rating method unchanged ---
  Future<Map<String, int>> getRatingEditCounts() async {
    final response = await _client
        .from('ratings')
        .select('shipment_id, edit_count');

    if (response.isNotEmpty) {
      final Map<String, int> editCounts = {};
      for (var row in response) {
        editCounts[row['shipment_id']] = row['edit_count'] as int;
      }
      return editCounts;
    }
    return {};
  }
}
