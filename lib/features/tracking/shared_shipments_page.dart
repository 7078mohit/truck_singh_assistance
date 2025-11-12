import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'shipment_tracking_page.dart';

class SharedShipmentsPage extends StatefulWidget {
  const SharedShipmentsPage({super.key});

  @override
  State<SharedShipmentsPage> createState() => _SharedShipmentsPageState();
}

class _SharedShipmentsPageState extends State<SharedShipmentsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _sharedShipments = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchSharedShipments();
  }

  Future<void> _fetchSharedShipments() async {
    try {
      final response = await Supabase.instance.client.rpc(
        'get_shipments_shared_with_me',
      );

      if (response != null && response is List) {
        final List<Map<String, dynamic>> allShipments =
        List<Map<String, dynamic>>.from(response);
        final now = DateTime.now();
        final filtered = allShipments.where((shipment) {
          final status = shipment['booking_status']?.toString().toLowerCase();
          final completedAtStr =
              shipment['completed_at'] ?? shipment['updated_at'];

          if (status == 'completed' && completedAtStr != null) {
            final completedAt = DateTime.tryParse(completedAtStr.toString());
            if (completedAt != null) {
              return now.difference(completedAt).inHours < 24;
            }
          }
          return true;
        }).toList();

        setState(() {
          _sharedShipments = filtered;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Could not fetch shared shipments: ${e.toString()}";
      });
      print(_errorMessage);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Shared With Me")),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
      );
    }

    if (_sharedShipments.isEmpty) {
      return const Center(
        child: Text(
          "No one has shared a shipment with you yet.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchSharedShipments,
      child: ListView.builder(
        itemCount: _sharedShipments.length,
        itemBuilder: (context, index) {
          final shipment = _sharedShipments[index];
          final sharerName = shipment['sharer_name'] ?? 'Someone';

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const Icon(
                Icons.local_shipping_outlined,
                color: Colors.teal,
              ),
              title: Text(
                shipment['shipment_id'] ?? 'Unknown ID',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                "Shared by: $sharerName\nStatus: ${shipment['booking_status'] ?? 'N/A'}",
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              isThreeLine: true,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ShipmentTrackingPage(
                      shipmentId: shipment['shipment_id'],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}