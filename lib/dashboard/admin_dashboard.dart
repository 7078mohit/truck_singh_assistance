import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../features/complains/mycomplain.dart';
import '../widgets/common/app_bar.dart';
import 'widgets/feature_card.dart';
import '../features/admin/manage_shipments_page.dart';
import '../features/admin/manage_trucks_page.dart';
import '../features/admin/manage_users_page.dart';
import '../features/admin/support_ticket_list_page.dart';
import '../features/admin/admin_user_management_page.dart';
import '../features/settings/presentation/screen/settings_page.dart';


Future<bool> shouldShowPopup() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String today = DateTime.now().toIso8601String().substring(0, 10);

  String? lastShown = prefs.getString("complaint_popup_last_shown");

  if (lastShown == today) return false;
  await prefs.setString("complaint_popup_last_shown", today);
  return true;
}

Future<Map<String, dynamic>> getComplaintStatus() async {
  final supabase = Supabase.instance.client;

  final data = await supabase
      .from("complaints")
      .select()
      .eq("status", "Open");

  int pending = data.length;

  int overdue = data.where((c) {
    final created = DateTime.parse(c['created_at']);
    return DateTime.now().difference(created).inDays > 7;
  }).length;

  return {
    "pending": pending,
    "overdue": overdue,
  };
}

void showComplaintAlertPopup(BuildContext context,
    {required int pending, required int overdue}) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text("Complaint Reminder"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pending > 0)
            Text("• You have $pending unresolved complaints."),
          if (overdue > 0)
            const SizedBox(height: 4),
          if (overdue > 0)
            const Text(
              "• Some complaints are overdue!",
              style: TextStyle(color: Colors.red),
            ),
        ],
      ),
      actions: [
        TextButton(
          child: const Text("VIEW"),
          onPressed: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ComplaintHistoryPage(),
              ),
            );
          },
        ),
        TextButton(
          child: const Text("OK"),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );
}


class AdminDashboardState {
  final bool isLoading;
  final String? error;
  final Map<String, dynamic> stats;
  final Map<String, dynamic>? adminProfile;

  AdminDashboardState({
    this.isLoading = true,
    this.error,
    this.stats = const {},
    this.adminProfile,
  });

  AdminDashboardState copyWith({
    bool? isLoading,
    String? error,
    Map<String, dynamic>? stats,
    Map<String, dynamic>? adminProfile,
  }) {
    return AdminDashboardState(
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      stats: stats ?? this.stats,
      adminProfile: adminProfile ?? this.adminProfile,
    );
  }
}

class AdminService {
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> getAdminProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception("No logged in user");

    final response = await _supabase
        .from('user_profiles')
        .select('*')
        .eq('user_id', user.id)
        .single();

    if (response == null) throw Exception("Profile not found");
    return response;
  }

  Future<Map<String, dynamic>> getDashboardStats() async {
    return await _supabase.rpc('get_admin_dashboard_stats');
  }
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final AdminService _adminService = AdminService();
  AdminDashboardState _state = AdminDashboardState(isLoading: true);

  @override
  void initState() {
    super.initState();
    _loadData();
    _triggerComplaintPopup();
  }

  void _triggerComplaintPopup() async {
    bool show = await shouldShowPopup();
    if (!show) return;

    final status = await getComplaintStatus();

    if (status["pending"] > 0 || status["overdue"] > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showComplaintAlertPopup(
          context,
          pending: status["pending"],
          overdue: status["overdue"],
        );
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _state = _state.copyWith(isLoading: true));

    try {
      final stats = await _adminService.getDashboardStats();
      final profile = await _adminService.getAdminProfile();

      if (mounted) {
        setState(() {
          _state = _state.copyWith(
            isLoading: false,
            stats: stats,
            adminProfile: profile,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
              () => _state =
              _state.copyWith(isLoading: false, error: e.toString()),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error loading data: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _buildBody(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return CustomAppBar(
      showProfile: true,
      userProfile: _state.adminProfile,
      isLoading: _state.isLoading,
      shipment: null,
      showMessages: false,
      onProfileTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const SettingsPage(),
          ),
        );
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildBody() {
    if (_state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Failed to load dashboard. Pull down to refresh.\n\nError: ${_state.error}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPerformanceOverviewCard(),
          const SizedBox(height: 20),
          _buildFeatureGrid(),
        ],
      ),
    );
  }

  Widget _buildPerformanceOverviewCard() {
    final numberFormat = NumberFormat.compact();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.tealBlue, AppColors.teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.teal.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'systemOverview'.tr(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildOverviewItem(
                  'totalUsers'.tr(),
                  numberFormat.format(_state.stats['total_users'] ?? 0),
                  Icons.people_alt_outlined,
                ),
              ),
              Expanded(
                child: _buildOverviewItem(
                  'totalShipments'.tr(),
                  numberFormat.format(_state.stats['total_shipments'] ?? 0),
                  Icons.local_shipping_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewItem(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureGrid() {
    final featureCards = <Widget>[
      FeatureCard(
        title: 'users'.tr(),
        subtitle: 'manageappusers'.tr(),
        icon: Icons.manage_accounts_outlined,
        color: AppColors.tealBlue,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ManageUsersPage()),
        ),
      ),
      FeatureCard(
        title: 'adminTeam'.tr(),
        subtitle: 'manageadminroles'.tr(),
        icon: Icons.admin_panel_settings_outlined,
        color: const Color(0xFF6A1B9A),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminUserManagementPage()),
        ),
      ),
      FeatureCard(
        title: 'support'.tr(),
        subtitle: 'viewtickets'.tr(),
        icon: Icons.support_agent_outlined,
        color: Colors.redAccent,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SupportTicketListPage()),
        ),
      ),
      FeatureCard(
        title: 'shipments'.tr(),
        subtitle: 'overseeallloads'.tr(),
        icon: Icons.inventory_2_outlined,
        color: AppColors.teal,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ManageShipmentsPage()),
        ),
      ),
      FeatureCard(
        title: 'all_complaints'.tr(),
        subtitle: 'view_history'.tr(),
        icon: Icons.feedback_outlined,
        color: Colors.red,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ComplaintHistoryPage()),
        ),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: featureCards.length,
      itemBuilder: (context, index) => featureCards[index],
    );
  }
}