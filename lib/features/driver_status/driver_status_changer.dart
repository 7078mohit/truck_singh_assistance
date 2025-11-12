import 'package:flutter/material.dart';
import 'package:logistics_toolkit/config/theme.dart';
import 'package:logistics_toolkit/features/tracking/driver_route_tracking.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart' as ptr;

class DriverStatusChanger extends StatefulWidget {
  final String driverId;

  const DriverStatusChanger({required this.driverId, super.key});

  @override
  State<DriverStatusChanger> createState() => _DriverStatusChangerState();
}

class _DriverStatusChangerState extends State<DriverStatusChanger> {
  final SupabaseClient supabase = Supabase.instance.client;
  Map<String, dynamic>? currentShipment;
  bool isLoading = false;
  final ptr.RefreshController _refreshController =
  ptr.RefreshController(initialRefresh: false);

  final List<Map<String, dynamic>> statusFlow = [
    {
      'status': 'accepted'.tr(),
      'icon': Icons.check_circle,
      'color': Colors.blue,
      'description': 'accepted_desc'.tr(),
    },
    {
      'status': 'en_route_pickup'.tr(),
      'icon': Icons.directions_car,
      'color': Colors.purple,
      'description': 'en_route_pickup_desc'.tr(),
    },
    {
      'status': 'arrived_pickup'.tr(),
      'icon': Icons.location_on,
      'color': Colors.cyan,
      'description': 'arrived_pickup_desc'.tr(),
    },
    {
      'status': 'loading'.tr(),
      'icon': Icons.upload,
      'color': Colors.amber,
      'description': 'loading_desc'.tr(),
    },
    {
      'status': 'Picked Up',
      'icon': Icons.done,
      'color': Colors.green,
      'description': 'picked_up_desc'.tr(),
    },
    {
      'status': 'in_transit'.tr(),
      'icon': Icons.local_shipping,
      'color': Colors.indigo,
      'description': 'in_transit_desc'.tr(),
    },
    {
      'status': 'arrived_drop'.tr(),
      'icon': Icons.place,
      'color': Colors.teal,
      'description': 'arrived_drop_desc'.tr(),
    },
    {
      'status': 'unloading'.tr(),
      'icon': Icons.download,
      'color': Colors.deepOrange,
      'description': 'unloading_desc'.tr(),
    },
    {
      'status': 'delivered'.tr(),
      'icon': Icons.done_all,
      'color': Colors.green,
      'description': 'delivered_desc'.tr(),
    },
    {
      'status': 'completed'.tr(),
      'icon': Icons.verified,
      'color': Colors.green,
      'description': 'completed_desc'.tr(),
    },
  ];

  @override
  void initState() {
    super.initState();
    fetchCurrentShipment();
  }

  Future<void> fetchCurrentShipment() async {
    setState(() {
      isLoading = true;
    });

    try {
      final response = await supabase
          .from('shipment')
          .select()
          .eq('assigned_driver', widget.driverId)
          .neq('booking_status', 'Completed')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      setState(() {
        currentShipment = response;
        isLoading = false;
      });
      _refreshController.refreshCompleted();
    } catch (e) {
      setState(() {
        currentShipment = null;
        isLoading = false;
      });
      _refreshController.refreshFailed();
    }
  }

  Future<void> updateStatus(String newStatus) async {
    if (currentShipment == null) return;

    setState(() {
      isLoading = true;
    });

    try {
      await supabase
          .from('shipment')
          .update({
        'booking_status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('shipment_id', currentShipment!['shipment_id']);

      // ✅ If the shipment was completed, clear it from view
      if (newStatus.toLowerCase() == 'completed') {
        currentShipment = null;
        if (mounted) setState(() {}); // ✅ Force rebuild safely
      } else {
        await fetchCurrentShipment();
        if (mounted) setState(() {}); // ✅ Ensure rebuild after refresh
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check, color: Colors.white),
              const SizedBox(width: 8),
              Text('Status updated: $newStatus'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status update error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  int getCurrentStatusIndex() {
    if (currentShipment == null) return -1;
    return statusFlow.indexWhere(
          (s) => s['status'] == currentShipment!['booking_status'],
    );
  }

  Widget buildProgressIndicator() {
    final currentIndex = getCurrentStatusIndex();
    if (currentIndex == -1) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: (currentIndex + 1) / statusFlow.length,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              statusFlow[currentIndex]['color'],
            ),
            minHeight: 6,
          ),
          const SizedBox(height: 8),
          Text(
            '${currentIndex + 1} of ${statusFlow.length} steps completed',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget buildCurrentStatusCard() {
    if (currentShipment == null) return const SizedBox.shrink();

    final currentStatus = currentShipment!['booking_status'];
    final statusData = statusFlow.firstWhere(
          (s) => s['status'] == currentStatus,
      orElse: () => statusFlow[0],
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: statusData['color'],
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: statusData['color'].withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(statusData['icon'], size: 48, color: Colors.white),
          const SizedBox(height: 12),
          Text(
            'current_status'.tr(),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            currentStatus,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            statusData['description'],
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomAppBar() {
    // Hide the TRACK button if shipment is completed or no shipment
    if (currentShipment == null ||
        currentShipment!['booking_status']?.toString().toLowerCase() ==
            'completed') {
      return const SizedBox.shrink(); // No bottom bar
    }

    return BottomAppBar(
      elevation: 10.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    DriverRouteTrackingPage(driverId: widget.driverId),
              ),
            );
          },
          icon: const Icon(Icons.map_outlined),
          label: const Text("TRACK"),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            backgroundColor: AppColors.orange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.0),
            ),
          ),
        ),
      ),
    );
  }

  // 🌓 Updated for dark mode
  Widget buildShipmentDetails() {
    if (currentShipment == null) return const SizedBox.shrink();

    final theme = Theme.of(context); // 🌓 Access theme
    final isDark = theme.brightness == Brightness.dark; // 🌓 Check mode
    final deliveryDate = DateTime.parse(currentShipment!['delivery_date']);
    final isUrgent = deliveryDate.difference(DateTime.now()).inDays <= 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceVariant.withOpacity(0.3) // 🌓 Dark bg
            : Colors.white, // 🌓 Light bg
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'shipment_details'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface, // 🌓 Text adaptive
                ),
              ),
              if (isUrgent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'urgent'.tr(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _buildDetailItem(
            Icons.confirmation_number,
            'shipment_id'.tr(),
            currentShipment!['shipment_id']
                .toString()
                .substring(0, 12)
                .toUpperCase(),
          ),
          _buildDetailItem(Icons.upload, 'pickup_location'.tr(),
              currentShipment!['pickup']),
          _buildDetailItem(
              Icons.download, 'drop_location'.tr(), currentShipment!['drop']),
          _buildDetailItem(
              Icons.inventory_2, 'item'.tr(), currentShipment!['shipping_item']),
          _buildDetailItem(Icons.category, 'material'.tr(),
              currentShipment!['material_inside']),
          _buildDetailItem(Icons.monitor_weight, 'weight'.tr(),
              '${currentShipment!['weight']} kg'),
          _buildDetailItem(Icons.local_shipping, 'truck_type'.tr(),
              currentShipment!['truck_type']),
          _buildDetailItem(Icons.schedule, 'pickup_time'.tr(),
              currentShipment!['pickup_time']),
          _buildDetailItem(
            Icons.calendar_today,
            'delivery_date'.tr(),
            DateFormat('MMM dd, yyyy').format(deliveryDate),
            isUrgent: isUrgent,
          ),
          if (currentShipment!['notes'] != null &&
              currentShipment!['notes'].isNotEmpty)
            _buildDetailItem(Icons.note_alt, 'special_notes'.tr(),
                currentShipment!['notes']),
        ],
      ),
    );
  }

  // 🌓 Updated for dark mode text
  Widget _buildDetailItem(IconData icon, String label, String value,
      {bool isUrgent = false}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isUrgent
                  ? Colors.red[50]
                  : isDark
                  ? Colors.grey[850]
                  : Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isUrgent
                  ? Colors.red
                  : theme.colorScheme.onSurface.withOpacity(0.7), // 🌓
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color:
                    theme.colorScheme.onSurface.withOpacity(0.7), // 🌓 Label
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color:
                    isUrgent ? Colors.red : theme.colorScheme.onSurface, // 🌓
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildActionButton() {
    if (currentShipment == null) return const SizedBox.shrink();

    final currentIndex = getCurrentStatusIndex();
    if (currentIndex == -1 || currentIndex >= statusFlow.length - 1) {
      return const SizedBox.shrink();
    }

    final nextStatus = statusFlow[currentIndex + 1];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      child: ElevatedButton(
        onPressed: isLoading ? null : () => updateStatus(nextStatus['status']),
        style: ElevatedButton.styleFrom(
          backgroundColor: nextStatus['color'],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
        ),
        child: isLoading
            ? const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(nextStatus['icon'], size: 24),
            const SizedBox(width: 8),
            Text(
              'Mark as ${nextStatus['status']}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('my_current_delivery'.tr()),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
      ),
      body: ptr.SmartRefresher(
        controller: _refreshController,
        onRefresh: fetchCurrentShipment,
        enablePullDown: true,
        enablePullUp: false,
        header: const ptr.WaterDropHeader(), // Nice pull-down animation
        child: isLoading && currentShipment == null
            ? const Center(child: CircularProgressIndicator())
            : currentShipment == null
            ? ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 100),
            Icon(Icons.assignment_turned_in, size: 80, color: Colors.grey),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'no_active_shipment'.tr(),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'no_shipments_assigned'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey[500]),
              ),
            ),
          ],
        )
            : SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              buildProgressIndicator(),
              buildCurrentStatusCard(),
              const SizedBox(height: 20),
              buildShipmentDetails(),
              buildActionButton(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomAppBar(),
    );
  }
}