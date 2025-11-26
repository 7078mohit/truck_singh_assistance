import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:logistics_toolkit/features/settings/presentation/screen/settings_page.dart';
import 'package:logistics_toolkit/widgets/common/app_bar.dart';
import 'package:permission_handler/permission_handler.dart' as handler;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../features/chat/driver_chat_list_page.dart';
import '../features/complains/mycomplain.dart';
import '../features/driver_status/driver_status_changer.dart';
import '../features/driver_documents/driver_documents_page.dart';
import '../features/truck_documents/truck_documents_page.dart';
import '../features/notifications/real_time_notification_service.dart';
import '../features/sos/company_driver_sos.dart';
import '../features/trips/myTrips_history.dart';
import '../services/driver/background_location_service.dart';
import '../services/onesignal_notification_service.dart';
import '../features/auth/services/supabase_service.dart';
import 'package:easy_localization/easy_localization.dart';

class CompanyDriverDb extends StatefulWidget {
  const CompanyDriverDb({super.key});
  @override
  State<CompanyDriverDb> createState() => _CompanyDriverDbState();
}

class _CompanyDriverDbState extends State<CompanyDriverDb> {
  final SupabaseClient supabase = Supabase.instance.client;

  Map<String, dynamic>? userProfile;
  bool isLoading = true;

  bool _isTrackingEnabled = false;

  Map<String, dynamic>? _activeShipment;
  bool _isShipmentLoading = true;
  RealtimeChannel? _shipmentChannel;

  final RealTimeNotificationService _notificationService = RealTimeNotificationService();
  StreamSubscription? _notificationSubscription;
  int unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeDashboard();
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _notificationService.dispose();
    if (_shipmentChannel != null) {
      Supabase.instance.client.removeChannel(_shipmentChannel!);
    }
    super.dispose();
  }

  Future<void> _initializeDashboard() async {
    await BackgroundLocationService.initializeService();
    await _loadPageData();
    initializeOneSignalAndStorePlayerIddriver();
  }

  Future<void> _loadPageData() async {
    await Future.wait([
      _loadUserProfile(),
      _checkInitialTrackingStatus(),
    ]);
  }

  Future<void> _handleRefresh() async {
    await Future.wait([
      _loadUserProfile(),
      _fetchUnreadCount(),
    ]);
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return null;

      return await supabase
          .from('user_profiles')
          .select('*')
          .eq('user_id', user.id)
          .single();
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      return null;
    }
  }

  Future<void> _loadUserProfile() async {
    final profile = await getUserProfile();

    if (!mounted) return;
    setState(() {
      userProfile = profile;
      isLoading = false;
    });

    await _fetchActiveShipment();
    _startNotificationListener(supabase.auth.currentUser?.id ?? '');
    _subscribeToShipmentChanges();
  }

  void _startNotificationListener(String userId) {
    _notificationService.startListening(userId);
    _notificationSubscription =
        _notificationService.notificationStream.listen((_) {
          _fetchUnreadCount();
        });
    _fetchUnreadCount();
  }

  Future<void> _fetchUnreadCount() async {
    try {
      final user = SupabaseService.getCurrentUser();
      if (user == null) return;

      final count = await SupabaseService.client
          .from('notifications')
          .count(CountOption.exact)
          .eq('user_id', user.id)
          .eq('read', false);

      if (!mounted) return;
      setState(() => unreadCount = count);
    } catch (e) {
      debugPrint("Error loading notification count: $e");
    }
  }

  Future<void> _fetchActiveShipment() async {
    final userCustomId = userProfile?['custom_user_id'];
    if (userCustomId == null) {
      if (!mounted) return;
      setState(() => _isShipmentLoading = false);
      return;
    }

    try {
      final response = await SupabaseService.client
          .from('shipment')
          .select()
          .eq('assigned_driver', userCustomId)
          .filter('booking_status', 'in', [
        'accepted',
        'en_route_to_pickup',
        'arrived_at_pickup',
        'in_transit',
      ])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _activeShipment = response;
        _isShipmentLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isShipmentLoading = false);
      _showErrorSnackBar("error_fetch_active_shipment".tr());
    }
  }

  void _subscribeToShipmentChanges() {
    final userCustomId = userProfile?['custom_user_id'];
    if (userCustomId == null) return;

    _shipmentChannel = Supabase.instance.client
        .channel('public:shipment')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'shipment',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'assigned_driver',
        value: userCustomId,
      ),
      callback: (_) => _fetchActiveShipment(),
    )
        .subscribe();
  }

  Future<void> _checkInitialTrackingStatus() async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!mounted) return;
    setState(() => _isTrackingEnabled = isRunning);
  }

  Future<void> _toggleTracking(bool value) async {
    if (value) {
      final allowed = await _handleLocationPermission();
      if (!allowed) return;
      await BackgroundLocationService.startService();
      _showSnackBar("tracking_service_started".tr());
    } else {
      BackgroundLocationService.stopService();
      _showSnackBar("tracking_service_stopped".tr());
    }

    if (!mounted) return;
    setState(() => _isTrackingEnabled = value);
  }

  Future<bool> _handleLocationPermission() async {
    if (await handler.Permission.notification.request().isDenied) {
      _showErrorSnackBar("error_notification_permission_required".tr());
      return false;
    }

    if (await handler.Permission.location.serviceStatus.isDisabled) {
      _showErrorSnackBar("error_enable_location_services".tr());
      handler.openAppSettings();
      return false;
    }

    if (await handler.Permission.location.request().isDenied) {
      _showErrorSnackBar("error_location_permission_required".tr());
      handler.openAppSettings();
      return false;
    }

    if (await handler.Permission.locationAlways.isDenied) {
      return false;
    }

    return true;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildCurrentTripCard(),
                const SizedBox(height: 20),
                _buildFeatureGrid(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTripCard() {
    if (_isShipmentLoading) {
      return const SizedBox(
        height: 150,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_activeShipment == null) {
      return Container(
        width: double.infinity,
        height: 150,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            "no_active_trip".tr(),
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(color: Colors.grey.shade500),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.teal, AppColors.teal.withOpacity(0.8)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.teal.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.radio_button_checked,
                  color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                'live_tracking'.tr(),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white),
              ),
              const Spacer(),
              Switch(
                value: _isTrackingEnabled,
                onChanged: _toggleTracking,
                activeTrackColor: AppColors.orange.withOpacity(0.5),
                activeColor: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${_activeShipment!['pickup']} → ${_activeShipment!['drop']}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'ID: ${_activeShipment!['shipment_id']} • Status: ${_activeShipment!['booking_status']}',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return CustomAppBar(
      showProfile: true,
      showNotifications: true,
      showMessages: true,
      userProfile: userProfile,
      isLoading: isLoading,
      shipment: _activeShipment,
      onProfileTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsPage()),
        );
      },
    );
  }

  Widget _buildFeatureGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.1,
      children: [
        _buildFeatureCard(
          title: 'shipments_title'.tr(),
          subtitle: 'shipments_subtitle'.tr(),
          icon: Icons.local_shipping_outlined,
          color: AppColors.orange,
          onTap: () {
            final userCustomId = userProfile?['custom_user_id'];
            if (userCustomId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DriverStatusChanger(driverId: userCustomId),
                ),
              );
            } else {
              _showErrorSnackBar("driver_id_not_loaded".tr());
            }
          },
        ),
        _buildFeatureCard(
          title: 'my_trips_title'.tr(),
          subtitle: 'my_trips_subtitle'.tr(),
          icon: Icons.route_outlined,
          color: Colors.blue,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyTripsHistory()),
            );
          },
        ),
        _buildFeatureCard(
          title: 'My Documents',
          subtitle: 'Upload personal documents',
          icon: Icons.person_outline,
          color: Colors.green,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DriverDocumentsPage()),
            );
          },
        ),
        _buildFeatureCard(
          title: 'Truck Documents',
          subtitle: 'View truck documents (when assigned)',
          icon: Icons.local_shipping_outlined,
          color: Colors.blue,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TruckDocumentsPage()),
            );
          },
        ),
        _buildFeatureCard(
          title: 'complaints_title'.tr(),
          subtitle: 'complaints_subtitle'.tr(),
          icon: Icons.report_problem_outlined,
          color: Colors.amber,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ComplaintHistoryPage()),
            );
          },
        ),
        _buildFeatureCard(
          title: 'sos_title'.tr(),
          subtitle: 'sos_subtitle'.tr(),
          icon: Icons.sos_outlined,
          color: Colors.red,
          onTap: () {
            if (_activeShipment == null) {
              _showErrorSnackBar("You are not on an active shipment.");
              return;
            }
            final agentId = _activeShipment!['assigned_agent'];
            if (agentId != null && agentId.toString().isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CompanyDriverEmergencyScreen(agentId: agentId),
                ),
              );
            } else {
              _showErrorSnackBar("No agent assigned to the current shipment.");
            }
          },
        ),
        _buildFeatureCard(
          title: 'my_chats_title'.tr(),
          subtitle: 'my_chats_subtitle'.tr(),
          icon: Icons.chat_bubble_outline,
          color: Colors.blue,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DriverChatListPage()),
          ),
        ),

      ],
    );
  }

  Widget _buildFeatureCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}