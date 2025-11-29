import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class ShipmentMonitor {
  final SupabaseClient client;
  final String driverId;
  final void Function(Map<String, dynamic>?) onShipmentUpdate;

  Timer? _timer;

  ShipmentMonitor({
    required SupabaseClient supabaseClient,
    required String customUserId,
    required this.onShipmentUpdate,
  }) : client = supabaseClient,
        driverId = customUserId;

  void start() {
    _check();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _check());
  }

  void stop() => _timer?.cancel();

  Future<void> _check() async {
    print('[ShipmentMonitor] Checking for new active shipment...');
    try {
      const statuses = [
        'Accepted',
        'En Route to Pickup',
        'Arrived at Pickup',
        'In Transit',
      ];

      final shipment = await client
          .from('shipment')
          .select()
          .eq('assigned_driver', driverId)
          .inFilter('booking_status', statuses)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      onShipmentUpdate(shipment);
    } catch (e) {
      print('[ShipmentMonitor] ❌ Error fetching shipment: $e');
    }
  }
}