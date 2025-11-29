import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:logistics_toolkit/config/config.dart';
import 'package:http/http.dart' as http;

class RouteService {
  final double truckKPL = 7.0;
  final double fuelPricePerLiter = 100.0;

  Future<List<RouteOption>> getTrafficAwareRoutes(
      LatLng start,
      LatLng end,
      ) async {
    const url = "https://routes.googleapis.com/directions/v2:computeRoutes";

    final requestBody = jsonEncode({
      "origin": {
        "location": {
          "latLng": {"latitude": start.latitude, "longitude": start.longitude},
        },
      },
      "destination": {
        "location": {
          "latLng": {"latitude": end.latitude, "longitude": end.longitude},
        },
      },
      "travelMode": "DRIVE",
      "routingPreference": "TRAFFIC_AWARE",
      "computeAlternativeRoutes": true,
      "routeModifiers": {"avoidTolls": false, "avoidHighways": false},
      "units": "METRIC",
    });

    final headers = {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": AppConfig.googleMapsApiKey,
      "X-Goog-FieldMask":
      "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.routeLabels",
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        body: requestBody,
        headers: headers,
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final routes = decoded['routes'] as List? ?? [];
        return routes.map(_parseRoute).toList();
      }

      return [];
    } catch (e) {
      print("❌ RouteService Error: $e");
      return [];
    }
  }

  RouteOption _parseRoute(dynamic data) {
    final distanceMeters = data['distanceMeters'] ?? 0;
    final durationText = data['duration'] ?? "0s";

    final durationSeconds = int.tryParse(durationText.replaceAll('s', '')) ?? 0;

    final km = distanceMeters / 1000;
    final liters = km / truckKPL;
    final tripCost = liters * fuelPricePerLiter;

    return RouteOption(
      polylineEncoded: data['polyline']?['encodedPolyline'] ?? "",
      durationSeconds: durationSeconds,
      distanceMeters: distanceMeters,
      fuelCost: tripCost,
      tags: (data['routeLabels'] as List?)?.cast<String>() ?? [],
    );
  }
}

class RouteOption {
  final String polylineEncoded;
  final int durationSeconds;
  final int distanceMeters;
  final double fuelCost;
  final List<String> tags;

  const RouteOption({
    required this.polylineEncoded,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.fuelCost,
    required this.tags,
  });

  String get durationFormatted {
    final mins = (durationSeconds / 60).round();
    return mins >= 60 ? "${mins ~/ 60}h ${mins % 60}m" : "$mins min";
  }
}