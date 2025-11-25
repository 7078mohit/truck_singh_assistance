import 'package:flutter/material.dart';
import 'complain_detail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart' as ptr;

class ComplaintHistoryPage extends StatefulWidget {
  final String? initialComplaintId;
  const ComplaintHistoryPage({super.key, this.initialComplaintId});

  @override
  State<ComplaintHistoryPage> createState() => _ComplaintHistoryPageState();
}

class _ComplaintHistoryPageState extends State<ComplaintHistoryPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> complaintsMade = [];
  List<Map<String, dynamic>> complaintsAgainst = [];
  List<Map<String, dynamic>> allComplaints = [];
  bool loading = true;
  String? error;
  TabController? _tabController;
  String? _currentUserRole;
  String _statusFilter = 'All';
  String _typeFilter = 'All';
  DateTimeRange? _dateRange;
  String _searchQuery = '';
  final ptr.RefreshController _refreshController =
  ptr.RefreshController(initialRefresh: false);

  @override
  void initState() {
    super.initState();
    fetchCurrentUserRoleAndComplaints();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.initialComplaintId != null && !loading) {
      final all = [...complaintsMade, ...complaintsAgainst, ...allComplaints];
      final complaint = all.firstWhere(
            (c) => c['id'] == widget.initialComplaintId,
        orElse: () => {},
      );
      if (complaint.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showComplaintDetails(complaint);
        });
      }
    }
  }

  Future<void> fetchCurrentUserRoleAndComplaints() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final profile = await supabase
          .from('user_profiles')
          .select('role, custom_user_id')
          .eq('user_id', user.id)
          .maybeSingle();

      _currentUserRole = profile?['role'];
      final customUserId = profile?['custom_user_id'];

      // Create tab controller after we know the role
      int tabCount = _isAdminOnly(_currentUserRole) ? 1 : 2;
      _tabController?.dispose();
      _tabController = TabController(length: tabCount, vsync: this);

      final madeRes = await supabase
          .from('complaints')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final againstRes = await supabase
          .from('complaints')
          .select()
          .eq('target_user_id', customUserId)
          .order('created_at', ascending: false);

      List<Map<String, dynamic>> allRes = [];
      if (_isAdminOnly(_currentUserRole)) {
        final all = await supabase
            .from('complaints')
            .select()
            .order('created_at', ascending: false);
        allRes = List<Map<String, dynamic>>.from(all);
      }

      setState(() {
        complaintsMade = List<Map<String, dynamic>>.from(madeRes);
        complaintsAgainst = List<Map<String, dynamic>>.from(againstRes);
        allComplaints = allRes;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    } finally {
      _refreshController.refreshCompleted();
    }
  }

  /// Admin detector (keeps compatibility with company role)
  bool _isAdminOnly(String? role) {
    if (role == null) return false;
    final r = role.toLowerCase();
    return r == 'company' || r.contains('admin');
  }

  /// NEW: only mark overdue if complaint is Open and older than 7 days
  bool _isOverdueOpenComplaint(Map<String, dynamic> c) {
    try {
      final status = (c['status'] ?? '').toString();
      if (status != 'Open') return false; // <-- critical: only Open

      final createdRaw = c['created_at'] ?? c['createdAt'] ?? c['createdAtUtc'];
      if (createdRaw == null) return false;

      final created = DateTime.tryParse(createdRaw.toString());
      if (created == null) return false;

      final createdLocal = created.toLocal();
      final limit = createdLocal.add(const Duration(days: 7));

      return DateTime.now().isAfter(limit);
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> _applyFilters(
      List<Map<String, dynamic>> complaints) {
    return complaints.where((c) {
      if (_statusFilter != 'All' && (c['status'] ?? 'Open') != _statusFilter)
        return false;

      if (_typeFilter != 'All' &&
          (c['complaint_type'] ?? 'Unknown') != _typeFilter.toLowerCase())
        return false;

      if (_dateRange != null && c['created_at'] != null) {
        final dt = DateTime.tryParse(c['created_at'])?.toLocal();
        if (dt == null ||
            dt.isBefore(_dateRange!.start) ||
            dt.isAfter(_dateRange!.end)) return false;
      }

      final q = _searchQuery.toLowerCase();
      if (q.isNotEmpty) {
        final subject = (c['subject'] ?? '').toString().toLowerCase();
        final complaint = (c['complaint'] ?? '').toString().toLowerCase();
        final userName = (c['target_user_name'] ?? '').toString().toLowerCase();
        if (!subject.contains(q) &&
            !complaint.contains(q) &&
            !userName.contains(q)) return false;
      }

      return true;
    }).toList();
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: _statusFilter,
                items: [
                  DropdownMenuItem(
                      value: 'All', child: Text('all_statuses'.tr())),
                  DropdownMenuItem(value: 'Open', child: Text('open'.tr())),
                  DropdownMenuItem(
                      value: 'Clarified', child: Text('clarified'.tr())),
                  DropdownMenuItem(
                      value: 'Resolved', child: Text('resolved'.tr())),
                  DropdownMenuItem(
                      value: 'Rejected', child: Text('rejected'.tr())),
                ],
                onChanged: (val) => setState(() => _statusFilter = val ?? 'All'),
              ),
              DropdownButton<String>(
                value: _typeFilter,
                items: [
                  DropdownMenuItem(value: 'All', child: Text('all_types'.tr())),
                  DropdownMenuItem(value: 'user', child: Text('user'.tr())),
                  DropdownMenuItem(
                      value: 'shipment', child: Text('shipment'.tr())),
                ],
                onChanged: (val) => setState(() => _typeFilter = val ?? 'All'),
              ),
              OutlinedButton(
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2023, 1, 1),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDateRange: _dateRange,
                  );
                  if (picked != null) setState(() => _dateRange = picked);
                },
                child: Text(
                  _dateRange == null
                      ? 'all_dates'.tr()
                      : '${_dateRange!.start.month}/${_dateRange!.start.day} - ${_dateRange!.end.month}/${_dateRange!.end.day}',
                ),
              ),
              if (_dateRange != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _dateRange = null),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'search_complaints'.tr(),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ],
      ),
    );
  }

  String _getDisplayRole(String role) {
    switch (role) {
      case 'company':
      case 'truckowner':
        return 'Agent';
      case 'shipper':
        return 'Shipper';
      case 'driver_individual':
      case 'driver_company':
        return 'Driver';
      default:
        return role;
    }
  }

  void showComplaintDetails(Map<String, dynamic> complaint) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ComplaintDetailsPage(complaint: complaint),
      ),
    );
  }

  Widget _buildComplaintList(
      List<Map<String, dynamic>> complaints, {
        bool showParties = false,
      }) {
    final filtered = _applyFilters(complaints);

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'no_complaints_found'.tr(),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'nothing_to_show'.tr(),
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final complaint = filtered[index];

        // Use local time for display and overdue calculation
        final created = DateTime.tryParse(complaint['created_at'] ?? '')
            ?.toLocal(); // may be null
        final isOverdue = _isOverdueOpenComplaint(complaint);

        int overdueDays = 0;
        if (created != null) {
          final limit = created.add(const Duration(days: 7));
          if (DateTime.now().isAfter(limit)) {
            overdueDays = DateTime.now().difference(limit).inDays;
          }
        }

        final displayDate = created;

        return Container(
          decoration: isOverdue
              ? BoxDecoration(
            border: Border.all(color: Colors.red.shade400, width: 2),
            borderRadius: BorderRadius.circular(12),
          )
              : null,
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            child: ListTile(
              leading: Stack(
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.report, color: Colors.white, size: 16),
                  ),
                  if (complaint['is_clarified'] == true)
                    const Positioned(
                      right: 0,
                      bottom: 0,
                      child: Icon(Icons.verified, color: Colors.green, size: 16),
                    ),
                ],
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      complaint['subject'] ?? 'No Subject',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Overdue badge: only for Open & > 7 days (NEW)
                  if (isOverdue)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "Overdue (${overdueDays} days)",
                        style: const TextStyle(
                            color: Colors.red,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),

                  if (_shouldShowStatusBadge(complaint))
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: complaint['status'] == 'Resolved'
                            ? Colors.green
                            : Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        complaint['status'] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (_shouldShowJustificationIndicator(complaint))
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    complaint['complaint'] ?? 'No details',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showParties) ...[
                    FutureBuilder(
                      future: _fetchUserNamesAndRoles(complaint),
                      builder:
                          (context, AsyncSnapshot<List<String>> snapshot) {
                        if (!snapshot.hasData) return const SizedBox.shrink();
                        final parties = snapshot.data!;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            'By: ${parties[0]}   |   Against: ${parties[1]}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'complaint'.tr(),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (displayDate != null)
                        Text(
                          DateFormat('MMM dd').format(displayDate),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              onTap: () => showComplaintDetails(complaint),
            ),
          ),
        );
      },
    );
  }

  bool _shouldShowStatusBadge(Map<String, dynamic> complaint) {
    return complaint['status'] == 'Resolved' ||
        complaint['status'] == 'Rejected';
  }

  bool _shouldShowJustificationIndicator(Map<String, dynamic> complaint) {
    return (complaint['agent_justification'] ?? '').toString().isNotEmpty &&
        complaint['status'] != 'Open' &&
        complaint['status'] != 'Clarified';
  }

  Future<List<String>> _fetchUserNamesAndRoles(
      Map<String, dynamic> complaint) async {
    final supabase = Supabase.instance.client;
    String complainer = '';
    String target = '';

    if (complaint['user_id'] != null) {
      final complainerProfile = await supabase
          .from('user_profiles')
          .select('name, role')
          .eq('user_id', complaint['user_id'])
          .maybeSingle();
      if (complainerProfile != null) {
        complainer = complainerProfile['name'] ?? '';
        final role = _getDisplayRole(complainerProfile['role']);
        complainer += role.isNotEmpty ? ' ($role)' : '';
      }
    }

    if (complaint['target_user_id'] != null) {
      final targetProfile = await supabase
          .from('user_profiles')
          .select('name, role')
          .eq('custom_user_id', complaint['target_user_id'])
          .maybeSingle();
      if (targetProfile != null) {
        target = targetProfile['name'] ?? '';
        final role = _getDisplayRole(targetProfile['role']);
        target += role.isNotEmpty ? ' ($role)' : '';
      }
    }

    return [complainer, target];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('complaint_history'.tr()),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        bottom: _tabController == null
            ? null
            : TabBar(
          controller: _tabController!,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.7),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.normal,
            fontSize: 14,
          ),
          tabs: [
            if (!_isAdminOnly(_currentUserRole)) ...[
              Tab(text: 'complaints_made'.tr()),
              Tab(text: 'complaints_against'.tr()),
            ],
            if (_isAdminOnly(_currentUserRole))
              Tab(text: 'all_complaints'.tr()),
          ],
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? _buildErrorWidget()
          : Column(
        children: [
          _buildFilters(),
          Expanded(
            child: _tabController == null
                ? const SizedBox()
                : ptr.SmartRefresher(
              controller: _refreshController,
              onRefresh: fetchCurrentUserRoleAndComplaints,
              enablePullDown: true,
              enablePullUp: false,
              header: const ptr.WaterDropHeader(),
              child: TabBarView(
                controller: _tabController!,
                children: [
                  if (!_isAdminOnly(_currentUserRole)) ...[
                    _buildComplaintList(complaintsMade),
                    _buildComplaintList(complaintsAgainst),
                  ],
                  if (_isAdminOnly(_currentUserRole))
                    _buildComplaintList(allComplaints,
                        showParties: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            'error_loading_complaints'.tr(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            error ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: fetchCurrentUserRoleAndComplaints,
            child: Text('retry'.tr()),
          ),
        ],
      ),
    );
  }
}