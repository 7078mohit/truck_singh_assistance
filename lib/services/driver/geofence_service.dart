import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../shipment_manager.dart';

class LatLng {
  final double latitude;
  final double longitude;
  LatLng(this.latitude, this.longitude);
}

class GeofenceService {
  static const double enRouteRadius = 5000;
  static const double arrivedRadius = 500;

  static Future<String?> checkGeofences(
      Position currentPosition,
      Map<String, dynamic> shipment,
      ) async {
    final pickupLat = shipment['pickup_lat'] as double?;
    final pickupLng = shipment['pickup_lng'] as double?;
    final dropLat = shipment['drop_lat'] as double?;
    final dropLng = shipment['drop_lng'] as double?;

    if ([pickupLat, pickupLng, dropLat, dropLng].contains(null)) {
      debugPrint(
        "❌ Missing geofence coordinates for shipment ${shipment['shipment_id']}",
      );
      return null;
    }
    final shipmentId = shipment['shipment_id'];
    final currentStatus = shipment['booking_status'] as String;

    final distanceToPickup = Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      pickupLat!,
      pickupLng!,
    );

    final distanceToDropoff = Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      dropLat!,
      dropLng!,
    );
    String? newStatus;
    switch (currentStatus) {
      case 'Accepted':
        if (distanceToPickup < enRouteRadius) newStatus = 'En Route to Pickup';
        break;

      case 'En Route to Pickup':
        if (distanceToPickup < arrivedRadius) newStatus = 'Arrived at Pickup';
        break;

      case 'Arrived at Pickup':
        if (distanceToPickup > arrivedRadius) newStatus = 'In Transit';
        break;

      case 'In Transit':
        if (distanceToDropoff < arrivedRadius) newStatus = 'Arrived at Drop';
        break;
    }

    if (newStatus != null) {
      await ShipmentManager.updateShipmentStatus(shipmentId, newStatus);
      return newStatus;
    }

    return null;
  }
}