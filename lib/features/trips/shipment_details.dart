import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:logistics_toolkit/features/auth/services/supabase_service.dart';
import 'package:logistics_toolkit/features/complains/complain_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:math';
import '../ratings/presentation/screen/rating.dart';
import '../tracking/shipment_tracking_page.dart';

class ShipmentDetailsPage extends StatefulWidget {
  final Map<String, dynamic> shipment;
  final bool isHistoryPage;

  const ShipmentDetailsPage({
    super.key,
    required this.shipment,
    this.isHistoryPage = false,
  });

  @override
  State<ShipmentDetailsPage> createState() => _ShipmentDetailsPageState();
}

class _ShipmentDetailsPageState extends State<ShipmentDetailsPage>
    with TickerProviderStateMixin {
  Timer? _trackingTimer;
  LatLng? _currentLocation;
  Map<String, int> ratingEditCount = {};

  late String currentUserCustomId;
  bool isFetchingUserId = true; // optional: for loading state

  bool get canShareTracking {
    if (isFetchingUserId) return false;

    final shipperId = widget.shipment['shipper_id'] ?? '';
    final assignedAgent = widget.shipment['assigned_agent'] ?? '';

    // ✅ Allow both shipper or agent to share
    return currentUserCustomId == shipperId ||
        currentUserCustomId == assignedAgent;
  }

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startLiveTracking();
    _fetchCurrentUserCustomId();
  }

  Future<void> _fetchCurrentUserCustomId() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => isFetchingUserId = true);

    final userId = user.id;
    final response = await Supabase.instance.client
        .from('user_profiles')
        .select('custom_user_id')
        .eq('user_id:: text', userId)
        .maybeSingle();

    if (response != null) {
      currentUserCustomId = (response['custom_user_id'] as String?)!;
    }

    // 🧩 Add these debug prints
    print('✅ currentUserCustomId: $currentUserCustomId');
    print('🚚 shipperId: ${widget.shipment['shipper_id']}');
    print('🧑‍💼 assignedAgent: ${widget.shipment['assigned_agent']}');

    setState(() => isFetchingUserId = false);
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  // function for complaint button visible
  bool get canFileComplaint {
    if (widget.isHistoryPage) return false;

    final status = widget.shipment['booking_status']?.toString().toLowerCase();
    final deliveryDateStr = widget.shipment['delivery_date'];
    final deliveryDate = DateTime.tryParse(deliveryDateStr ?? '');

    // Complaint allowed for all active (non-completed) shipments
    if (status != 'completed') return true;

    // Complaint allowed up to 7 days after completion
    if (deliveryDate == null) return false;
    return DateTime.now().difference(deliveryDate).inDays <= 7;
  }

  void _startLiveTracking() {
    _trackingTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      // Simulate vehicle movement
      if (_currentLocation != null) {
        double newLat =
            _currentLocation!.latitude + (Random().nextDouble() - 0.5) * 0.001;
        double newLng =
            _currentLocation!.longitude + (Random().nextDouble() - 0.5) * 0.001;

        setState(() {
          _currentLocation = LatLng(newLat, newLng);
        });
      }
    });
  }

  String getFormattedDate(String? dateStr) {
    final date = DateTime.tryParse(dateStr ?? '') ?? DateTime.now();
    return DateFormat('dd MMM yyyy, hh:mm a').format(date);
  }

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'en route to pickup':
      case 'arrived at pickup':
      case 'loading':
      case 'picked up':
      case 'in transit':
      case 'arrived at drop':
      case 'unloading':
        return Colors.purple;
      case 'delivered':
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.pending;
      case 'accepted':
        return Icons.check_circle;
      case 'en route to pickup':
        return Icons.local_shipping;
      case 'arrived at pickup':
        return Icons.location_on;
      case 'loading':
        return Icons.upload;
      case 'picked up':
        return Icons.done;
      case 'in transit':
        return Icons.directions_bus;
      case 'arrived at drop':
        return Icons.place;
      case 'unloading':
        return Icons.download;
      case 'delivered':
        return Icons.done_all;
      case 'completed':
        return Icons.verified;
      default:
        return Icons.info;
    }
  }

  Future<void> _showShareTrackingDialog() async {
    final formKey = GlobalKey<FormState>();
    final recipientController = TextEditingController();
    bool isSharing = false; // For loading state within the dialog

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Share Shipment Tracking'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text(
                        'Enter the User ID, Name, or Mobile Number of the person you want to share this shipment with.',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: recipientController,
                        decoration: const InputDecoration(
                          labelText: 'User ID / Name / Mobile',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter an identifier.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  icon: isSharing
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Icon(Icons.share),
                  label: const Text('Share'),
                  onPressed: isSharing
                      ? null
                      : () async {
                    if (!formKey.currentState!.validate()) return;

                    setStateDialog(() => isSharing = true);
                    final recipient = recipientController.text.trim();

                    // 🧩 Prevent sharing with yourself
                    if (recipient == currentUserCustomId) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('You cannot share tracking with yourself'),
                        ),
                      );
                      setStateDialog(() => isSharing = false);
                      return;
                    }

                    try {
                      // ✅ Get current user's custom ID
                      final String? sharerId =
                      await SupabaseService.getCustomUserId(
                        Supabase.instance.client.auth.currentUser!.id,
                      );

                      if (sharerId == null) {
                        throw Exception("Could not get the current user's ID.");
                      }

                      // ✅ Call the RPC with correct parameters
                      final response = await Supabase.instance.client.rpc(
                        'share_shipment_track',
                        params: {
                          'p_shipment_id': widget.shipment['shipment_id'],
                          'p_sharer_user_id': sharerId,
                          'p_recipient_identifier': recipient,
                        },
                      );

                      final status = response['status'];
                      final message = response['message'];

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(message),
                            backgroundColor:
                            status == 'success' ? Colors.green : Colors.red,
                          ),
                        );
                        if (status == 'success') {
                          Navigator.of(context).pop();
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('An error occurred: ${e.toString()}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } finally {
                      setStateDialog(() => isSharing = false);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }


  @override
  void dispose() {
    _trackingTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String shipmentID = widget.shipment['shipment_id'];
    final initialEditCount = widget.shipment['edit_count'] as int? ?? 0;
    final currentEditCount =
        ratingEditCount[shipmentID] ?? initialEditCount;
    bool isCompleted =
        widget.shipment['booking_status'].toString().toLowerCase() ==
            'completed';
    bool editLimitReached = currentEditCount >= 3;
    final deliveryDate = DateTime.tryParse(
      widget.shipment['delivery_date'] ?? '',
    );
    final bool isRatingPeriodExpired =
        deliveryDate != null &&
            DateTime.now().isAfter(deliveryDate.add(const Duration(days: 107)));
    final bool canRate =
        isCompleted && !editLimitReached && !isRatingPeriodExpired;
    return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text('shipmentDetails'.tr()),
          elevation: 0,
          actions: [
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                });
              },
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: EdgeInsets.all(16),
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        getStatusColor(widget.shipment['booking_status']),
                        getStatusColor(
                          widget.shipment['booking_status'],
                        ).withValues(alpha: 7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: getStatusColor(
                          widget.shipment['booking_status'],
                        ).withValues(alpha: 3),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _pulseAnimation.value,
                                child: Icon(
                                  getStatusIcon(widget.shipment['booking_status']),
                                  size: 32,
                                ),
                              );
                            },
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.shipment['booking_status'] ??
                                      'unknown'.tr(),
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${'shipmentID'.tr()}: ${widget.shipment['shipment_id']}',
                                  style: TextStyle(
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                //live tracking container that is clickable and redirect to live tracking page
                if (widget.shipment['booking_status'] != 'Completed')
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ShipmentTrackingPage(
                            shipmentId: widget.shipment['shipment_id'],
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        //color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  color: Colors.red,
                                  size: 24,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'liveTracking'.tr(),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.touch_app,
                                  color: Colors.grey[600],
                                  size: 16,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'tapToOpenLiveTracking'.tr(),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                SizedBox(height: 16),
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 16),
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    //color: Colors.white,
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'shipmentInformation'.tr(),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 16),

                      _buildInfoRow(
                        Icons.location_on,
                        'pickupLocation'.tr(),
                        widget.shipment['pickup'] ?? 'nA'.tr(),
                      ),
                      _buildInfoRow(
                        Icons.place,
                        'dropLocation'.tr(),
                        widget.shipment['drop'] ?? 'nA'.tr(),
                      ),
                      _buildInfoRow(
                        Icons.calendar_today,
                        'pickupDate'.tr(),
                        getFormattedDate(widget.shipment['created_at']),
                      ),
                      _buildInfoRow(
                        Icons.calendar_today,
                        'deliveryDate'.tr(),
                        getFormattedDate(widget.shipment['delivery_date']),
                      ),
                      _buildInfoRow(
                        Icons.access_time,
                        'pickupTime'.tr(),
                        widget.shipment['pickup_time'] ?? 'nA'.tr(),
                      ),

                      if (widget.shipment['assigned_company'] != null)
                        _buildInfoRow(
                          Icons.business,
                          'assignedCompany'.tr(),
                          widget.shipment['assigned_company'],
                        ),
                      if (widget.shipment['assigned_agent'] != null)
                        _buildInfoRow(
                          Icons.person,
                          'assignedAgent'.tr(),
                          widget.shipment['assigned_agent'],
                        ),
                      if (widget.shipment['assigned_driver'] != null)
                        _buildInfoRow(
                          Icons.drive_eta,
                          'assignedDriver'.tr(),
                          widget.shipment['assigned_driver'],
                        ),
                    ],
                  ),
                ),

                SizedBox(height: 16),

                // Action Buttons
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // ## New Share Tracking Button
                      if (widget.shipment['booking_status'] != 'Completed' &&
                          canShareTracking) ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.share),
                            label: const Text('Share Tracking'),
                            onPressed: _showShareTrackingDialog,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Complaint Button below
                      if (canFileComplaint)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.report_problem),
                            label: Text('fileAComplaint'.tr()),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ComplaintPage(
                                    preFilledShipmentId:
                                    widget.shipment['shipment_id'],
                                    editMode: false,
                                    complaintData: {},
                                  ),
                                ),
                              );
                            },

                            //Rating button below
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
                      SizedBox(height: 12),
                      if (canRate)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.star),
                            label: Text(
                              isRatingPeriodExpired
                                  ? 'ratingPeriodExpired'.tr()
                                  : (editLimitReached
                                  ? 'editLimitReached'.tr()
                                  : (currentEditCount == 0
                                  ? 'rateThisShipment'.tr()
                                  : '${'editRating'.tr()} ($currentEditCount/3)')),
                              style: const TextStyle(fontSize: 14),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: canRate
                                  ? Colors.blue
                                  : Colors.grey[400],
                              foregroundColor: canRate
                                  ? Colors.black
                                  : Colors.grey[700],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadiusGeometry.circular(20),
                              ),
                            ),
                            onPressed: canRate
                                ? () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => Rating(
                                    shipmentId:
                                    widget.shipment['shipment_id'],
                                  ),
                                ),
                              );

                              if (result != null && result is int) {
                                // Update the local state
                                setState(() {
                                  ratingEditCount[shipmentID] = result;
                                });

                                // Show snackbar
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'ratingSavedSuccessfully'.tr(),
                                      ),
                                    ),
                                  );
                                }
                                Navigator.pop(context, result);
                              }
                            }
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 24),
              ],
            ),
          ),
        )
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey[600], size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}