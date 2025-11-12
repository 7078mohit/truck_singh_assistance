import 'package:flutter/material.dart';
import 'package:logistics_toolkit/features/mydrivers/addDriver.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart' as ptr;

//other page imports

class Driver {
  final String id;
  final String name;
  final String contact;
  final String status;
  final double? rating;

  Driver({
    required this.id,
    required this.name,
    required this.contact,
    required this.status,
    this.rating,
  });

  Color get statusColor {
    switch (status) {
      case 'Available':
        return Colors.green;
      case 'On Trip':
        return Colors.blue;
      case 'Leave':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData get statusIcon {
    switch (status) {
      case 'Available':
        return Icons.check_circle;
      case 'On Trip':
        return Icons.directions_car;
      case 'Leave':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  factory Driver.fromMap(Map<String, dynamic> map) {
    final bookingStatus = (map['booking_status'] ?? 'no_shipment')
        .toString()
        .toLowerCase();

    String driverStatus;

    // Driver is AVAILABLE only when:
    // 1. They have no shipment assigned, OR
    // 2. Their last shipment is completed
    if (bookingStatus == 'no_shipment' ||
        bookingStatus == 'completed' ||
        bookingStatus == 'delivered' ||
        bookingStatus == 'cancelled') {
      driverStatus = 'Available';
    } else {
      // Driver is ON TRIP for all other statuses:
      // pending, accepted, en route to pickup, arrived at pickup,
      // loading, picked up, in transit, arrived at drop, unloading, delivered
      driverStatus = 'On Trip';
    }

    // --- THIS IS THE FIX ---
    // Use the correct keys from the 'user_profiles' table
    return Driver(
      id: (map['custom_user_id'] ?? '').toString(),
      name: map['name'] ?? 'Unknown', // Use 'name'
      contact: map['mobile_number'] ?? '', // Use 'mobile_number'
      status: driverStatus,
      rating: map['avg_driver_rating'] != null
          ? double.tryParse(map['avg_driver_rating'].toString())
          : null,
    );
  }
}

class MyDriverPage extends StatefulWidget {
  final bool isSelectionMode;
  final String? shipmentId;

  const MyDriverPage({
    super.key,
    this.isSelectionMode = false,
    this.shipmentId,
  });

  @override
  _MyDriverPageState createState() => _MyDriverPageState();
}

class _MyDriverPageState extends State<MyDriverPage>
    with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Driver> drivers = [];
  bool isLoading = true;
  String loggedInOwnerCustomId = '';

  bool sortByRating = false;
  bool sortByStatus = false;
  int _totalDrivers = 0;
  int availableDrivers = 0;
  int onTripDrivers = 0;
  int onLeaveDrivers = 0;
  String selectedFilter = 'All Drivers';
  bool isFirstTime = true;
  final ptr.RefreshController _refreshController =
  ptr.RefreshController(initialRefresh: false);

  @override
  void initState() {
    super.initState();
    // When in selection mode (assign driver), default to showing only available drivers
    if (widget.isSelectionMode) {
      selectedFilter = 'available_only'.tr();
    } else {
      checkFirstTime();
    }
    fetchLoggedInOwnerId();
  }

  Future<void> checkFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    isFirstTime = prefs.getBool('first_time_add_driver') ?? true;
    if (isFirstTime) {
      await prefs.setBool('first_time_add_driver', false);
    }
    setState(() {});
  }

  Future<void> fetchLoggedInOwnerId() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final response = await supabase
        .from('user_profiles')
        .select('custom_user_id')
        .eq('user_id', user.id)
        .maybeSingle();

    if (response != null) {
      loggedInOwnerCustomId = response['custom_user_id'];
      fetchDriversFromSupabase();
    }
  }

  // --- THIS IS THE UPDATED FUNCTION ---
  Future<void> fetchDriversFromSupabase() async {
    if (loggedInOwnerCustomId.isEmpty) return;
    setState(() => isLoading = true);
    try {
      // 1. Get all driver_custom_ids for this owner
      final relationResponse = await supabase
          .from('driver_relation')
          .select('driver_custom_id')
          .eq('owner_custom_id', loggedInOwnerCustomId);

      final driverIds = relationResponse
          .map((row) => row['driver_custom_id'] as String)
          .toList();

      if (driverIds.isEmpty) {
        setState(() {
          drivers = [];
          _totalDrivers = 0;
          availableDrivers = 0;
          onTripDrivers = 0;
          onLeaveDrivers = 0;
          isLoading = false;
        });
        return;
      }

      // 2. Loop through each driver ID and fetch their profile and status
      List<Map<String, dynamic>> driversWithStatus = [];

      // --- LOGIC FIX HERE ---
      // Define all known "active" statuses. This is safer than a .not() query.
      // We include lowercase and title-case for safety.
      final activeStatuses = [
        'pending',
        'accepted',
        'en route to pickup',
        'arrived at pickup',
        'loading',
        'picked up',
        'in transit',
        'arrived at drop',
        'unloading',
        'Pending',
        'Accepted',
        'En Route to Pickup',
        'Arrived at Pickup',
        'Loading',
        'Picked Up',
        'In Transit',
        'Arrived at Drop',
        'Unloading'
      ];
      // --- END LOGIC FIX ---

      for (var driverCustomId in driverIds) {

        // Fetch the driver's profile
        final profileResponse = await supabase
            .from('user_profiles')
            .select('name, custom_user_id, mobile_number')
            .eq('custom_user_id', driverCustomId)
            .maybeSingle(); // Use maybeSingle to get one profile or null

        if (profileResponse == null) {
          continue; // Skip if profile not found
        }

        // --- SYNTAX FIX HERE ---
        // Find any shipment that IS IN one of the active states.
        // We use the .filter() syntax from your driver_chat_service.dart
        final shipmentResponse = await supabase
            .from('shipment')
            .select('booking_status') // Select FIRST
            .eq('assigned_driver', driverCustomId) // Filter SECOND
            .filter('booking_status', 'in', activeStatuses) // Filter THIRD
            .limit(1);
        // --- END SYNTAX FIX ---

        // Add booking status to the driver's profile map
        final driverData = Map<String, dynamic>.from(profileResponse);
        if (shipmentResponse.isNotEmpty) {
          // Driver has at least one active shipment
          driverData['booking_status'] =
          shipmentResponse[0]['booking_status'];
        } else {
          // Driver has no active shipments
          driverData['booking_status'] = 'no_shipment';
        }

        // Note: avg_driver_rating is not fetched here.
        // If you need rating, you must add it to the 'user_profiles' select
        // and add 'avg_driver_rating': driverProfile['avg_driver_rating']

        driversWithStatus.add(driverData);
      }

      List<Driver> fetchedDrivers = driversWithStatus
          .map((item) => Driver.fromMap(item as Map<String, dynamic>))
          .toList();

      setState(() {
        drivers = fetchedDrivers;
        _totalDrivers = drivers.length;
        availableDrivers = fetchedDrivers
            .where((d) => d.status == 'Available')
            .length;
        onTripDrivers = fetchedDrivers
            .where((d) => d.status == 'On Trip')
            .length;
        onLeaveDrivers = fetchedDrivers
            .where((d) => d.status == 'Leave')
            .length;
        isLoading = false;
      });_refreshController.refreshCompleted();
    } catch (e) {
      setState(() => isLoading = false);
      _refreshController.refreshFailed();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error fetching drivers: $e')));
      }
    }
  }
  // --- END OF UPDATED FUNCTION ---

  List<Driver> get filteredDrivers {
    List<Driver> filtered = drivers.where((driver) {
      if (selectedFilter == 'Available Only' ||
          selectedFilter == 'available_only'.tr())
        return driver.status == 'Available';
      if (selectedFilter == 'On Trip' || selectedFilter == 'on_trip'.tr())
        return driver.status == 'On Trip';
      if (selectedFilter == 'On Leave' || selectedFilter == 'on_leave'.tr())
        return driver.status == 'Leave';
      return true;
    }).toList();

    if (sortByRating) {
      filtered.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    } else if (sortByStatus) {
      final order = {'Available': 0, 'On Trip': 1, 'Leave': 2};
      filtered.sort(
            (a, b) => (order[a.status] ?? 99).compareTo(order[b.status] ?? 99),
      );
    }
    return filtered;
  }

  void _selectDriver(Driver driver) {
    if (!widget.isSelectionMode || driver.status != 'Available') return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('confirm_driver_assignment'.tr()),
          content: Text(
            'Assign ${driver.name} to shipment ${widget.shipmentId ?? ''}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('cancel'.tr()),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                // [FIXED] Implemented the correct logic from your reference code.
                Navigator.of(context).pop(driver.id);
              },
              child: Text('confirm'.tr()),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(String label, int count, Color color, String filter) {
    return GestureDetector(
      onTap: () => setState(() => selectedFilter = filter),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: selectedFilter == filter
              ? color.withOpacity(0.1)
              : Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selectedFilter == filter ? color : Colors.grey.shade200,
            width: selectedFilter == filter ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: color),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isSelectionMode
              ? 'select_driver'.tr()
              : 'driver_status_list'.tr(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              showSearch(
                context: context,
                delegate: DriverSearchDelegate(
                  drivers,
                  isSelectionMode: widget.isSelectionMode,
                ),
              );
            },
          ),
          /*IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchDriversFromSupabase,
          ),*/
          PopupMenuButton<String>(
            onSelected: (value) => setState(() {
              sortByRating = value == 'Rating';
              sortByStatus = value == 'Status';
            }),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'rating'.tr(),
                child: Text('sort_by_rating'.tr()),
              ),
              PopupMenuItem(
                value: 'status'.tr(),
                child: Text('sort_by_rating'.tr()),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: widget.isSelectionMode
          ? null
          : Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isFirstTime)
            Text(
              "tap_to_add_driver".tr(),
              style: TextStyle(fontSize: 12),
            ).animate().fade().slide(),
          const SizedBox(height: 4),
          Animate(
            effects: [
              ScaleEffect(duration: 600.ms, end: const Offset(1.1, 1.1)),
            ],
            onPlay: (controller) => controller.repeat(reverse: true),
            child: FloatingActionButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddDriverPage()),
                );
                fetchDriversFromSupabase();
              },
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatCard(
                  "total".tr(),
                  _totalDrivers,
                  Colors.cyan,
                  'all_drivers'.tr(),
                ),
                _buildStatCard(
                  "available".tr(),
                  availableDrivers,
                  Colors.green,
                  'available_only'.tr(),
                ),
                _buildStatCard(
                  "on_trip".tr(),
                  onTripDrivers,
                  Colors.blue,
                  'on_trip'.tr(),
                ),
                _buildStatCard(
                  "on_leave".tr(),
                  onLeaveDrivers,
                  Colors.red,
                  'on_leave'.tr(),
                ),
              ],
            ),
          ),
          if (widget.isSelectionMode)
            Container(
              width: double.infinity,
              color: Colors.green.shade50,
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Text(
                    'please_select_driver'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Showing only available drivers (not assigned to other shipments)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.green.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ptr.SmartRefresher(
              controller: _refreshController,
              onRefresh: fetchDriversFromSupabase,
              enablePullDown: true,
              enablePullUp: false,
              header: const ptr.WaterDropHeader(),
              child: filteredDrivers.isEmpty
                  ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 200),
                  Center(
                    child: Text(
                      'no_drivers_found'.tr(),
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ),
                ],
              )
                  : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: filteredDrivers.length,
                itemBuilder: (context, index) {
                  final driver = filteredDrivers[index];
                  final isAvailable = driver.status == 'Available';
                  return Slidable(
                    key: ValueKey(driver.id),
                    endActionPane: widget.isSelectionMode
                        ? null
                        : ActionPane(
                      motion: const ScrollMotion(),
                      children: [
                        SlidableAction(
                          onPressed: (context) async {
                            final contact = driver.contact.trim();
                            final uri = Uri.parse('tel:$contact');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                  Text("could_not_open_dialer".tr()),
                                ),
                              );
                            }
                          },
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          icon: Icons.call,
                          label: 'Call',
                        ),
                      ],
                    ),
                    child: Card(
                      margin: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 10,
                      ),
                      child: ListTile(
                        onTap: () {
                          if (widget.isSelectionMode && isAvailable) {
                            _selectDriver(driver);
                          }
                        },
                        leading: CircleAvatar(
                          backgroundColor:
                          driver.statusColor.withOpacity(0.2),
                          child: Icon(driver.statusIcon, color: driver.statusColor),
                        ),
                        title: Text(
                          '${driver.name} (${driver.id})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.phone, size: 16),
                                const SizedBox(width: 4),
                                Text(driver.contact),
                              ],
                            ),
                            if (driver.rating != null)
                              Row(
                                children: [
                                  const Icon(Icons.star,
                                      color: Colors.amber, size: 16),
                                  const SizedBox(width: 4),
                                  Text(driver.rating!.toStringAsFixed(1)),
                                ],
                              ),
                          ],
                        ),
                        trailing: widget.isSelectionMode
                            ? (isAvailable
                            ? ElevatedButton(
                          onPressed: () => _selectDriver(driver),
                          child: Text('select'.tr()),
                        )
                            : Text('unavailable'.tr(),
                            style: const TextStyle(color: Colors.grey)))
                            : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(driver.statusIcon,
                                color: driver.statusColor),
                            Text(driver.status,
                                style: TextStyle(color: driver.statusColor)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DriverSearchDelegate extends SearchDelegate<String?> {
  final List<Driver> allDrivers;
  final bool isSelectionMode;

  DriverSearchDelegate(this.allDrivers, {required this.isSelectionMode});

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    // [FIXED] The search logic is updated here.
    final results = allDrivers.where((driver) {
      final queryLower = query.toLowerCase();
      final nameMatches = driver.name.toLowerCase().contains(queryLower);
      final contactMatches = driver.contact.contains(queryLower);

      // A driver is included in the results if the name OR the contact matches.
      return nameMatches || contactMatches;
    }).toList();

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final driver = results[index];
        final isAvailable = driver.status == 'Available';

        return ListTile(
          title: Text(driver.name),
          subtitle: Text(driver.contact),
          trailing: Text(
            driver.status,
            style: TextStyle(color: driver.statusColor),
          ),
          enabled: isSelectionMode ? isAvailable : true,
          onTap: () {
            if (isSelectionMode) {
              if (isAvailable) {
                close(context, driver.id);
              }
            } else {
              close(context, null);
            }
          },
        );
      },
    );
  }
}