import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'complain_screen.dart';

class ComplaintDetailsPage extends StatefulWidget {
  final Map<String, dynamic> complaint;
  const ComplaintDetailsPage({super.key, required this.complaint});

  @override
  State<ComplaintDetailsPage> createState() => _ComplaintDetailsPageState();
}

class _ComplaintDetailsPageState extends State<ComplaintDetailsPage> {
  late Map<String, dynamic> _currentComplaint;
  String? _currentUserRole;
  bool _isActionLoading = false;
  bool _isLoading = true;
  RealtimeChannel? _complaintChannel;

  @override
  void initState() {
    super.initState();
    _currentComplaint = widget.complaint;
    _initializePage();
  }

  @override
  void dispose() {
    if (_complaintChannel != null) {
      Supabase.instance.client.removeChannel(_complaintChannel!);
    }
    super.dispose();
  }

  Future<void> _initializePage() async {
    await _fetchCurrentUserRole();
    setupRealtimeSubscription();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchCurrentUserRole() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final profile = await Supabase.instance.client
          .from('user_profiles')
          .select('role')
          .eq('user_id', user.id)
          .single();

      if (mounted) {
        setState(() {
          _currentUserRole = profile['role'];
        });
      }
    } catch (_) {}
  }

  void setupRealtimeSubscription() {
    final complaintId = _currentComplaint['id'];
    if (complaintId == null) return;

    final channelName = 'complaint-details:$complaintId';
    _complaintChannel = Supabase.instance.client.channel(channelName);

    _complaintChannel!
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'complaints',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: complaintId,
      ),
      callback: (payload) {
        if (!mounted) return;

        if (payload.eventType == 'UPDATE') {
          setState(() => _currentComplaint = payload.newRecord);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('complaint_updated'.tr()),
              backgroundColor: Colors.blue,
            ),
          );
        } else if (payload.eventType == 'DELETE') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('complaint_deleted'.tr()),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pop(context);
        }
      },
    ).subscribe();
  }

  Future<void> _refreshComplaint() async {
    try {
      final freshData = await Supabase.instance.client
          .from('complaints')
          .select()
          .eq('id', _currentComplaint['id'])
          .single();

      if (mounted) {
        setState(() => _currentComplaint = freshData);
      }
    } catch (_) {}
  }

  bool _isAgent(String? role) => role == 'company' || role == 'truckowner';

  Future<void> _performAction(Future<void> Function() action) async {
    setState(() => _isActionLoading = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  void _editComplaint() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ComplaintPage(
          editMode: true,
          complaintData: _currentComplaint,
          preFilledShipmentId: _currentComplaint['shipment_id'],
        ),
      ),
    );
  }

  Future<void> _deleteComplaint() async {
    final confirmed = await _showConfirmationDialog(
      'delete_complaint'.tr(),
      'delete_warning'.tr(),
      isDestructive: true,
    );

    if (confirmed != true) return;

    _performAction(() async {
      await Supabase.instance.client
          .from('complaints')
          .delete()
          .eq('id', _currentComplaint['id']);

      final attachmentUrl = _currentComplaint['attachment_url'];
      if (attachmentUrl != null) {
        final pathMatch = RegExp(
          r'/storage/v1/object/public/complaint-attachments/(.+)',
        ).firstMatch(attachmentUrl);

        if (pathMatch != null) {
          final filePath = pathMatch.group(1);
          if (filePath != null) {
            await Supabase.instance.client.storage
                .from('complaint-attachments')
                .remove([filePath]);
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('complaint_deleted_success'.tr()),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    });
  }

  Future<void> _handleAgentAction(
      String action, String title, String eventType, String eventTitle) async {
    final controller = TextEditingController();
    final confirmed = await _showJustificationDialog(title, action, controller);

    if (confirmed != true) return;

    _performAction(() async {
      final time = DateTime.now().toIso8601String();

      final historyEvent = {
        'type': eventType,
        'title': eventTitle,
        'description': controller.text.trim(),
        'timestamp': time,
        'user_id': Supabase.instance.client.auth.currentUser?.id,
      };

      final existing = _currentComplaint['history'] as Map? ?? {};
      final events = List.from(existing['events'] ?? []);
      events.add(historyEvent);

      await Supabase.instance.client.from('complaints').update({
        'status': eventTitle,
        'agent_justification': controller.text.trim(),
        'history': {'events': events},
      }).eq('id', _currentComplaint['id']);

      await _refreshComplaint();
    });
  }

  Future<void> _appealComplaint() async {
    final confirmed = await _showConfirmationDialog(
      'appeal_decision'.tr(),
      'appeal_warning'.tr(),
    );

    if (confirmed != true) return;

    _performAction(() async {
      final time = DateTime.now().toIso8601String();

      final historyEvent = {
        'type': 'appealed',
        'title': 'Decision Appealed',
        'description': 'Status reverted to "Open"',
        'timestamp': time,
        'user_id': Supabase.instance.client.auth.currentUser?.id,
      };

      final existing = _currentComplaint['history'] as Map? ?? {};
      final events = List.from(existing['events'] ?? []);
      events.add(historyEvent);

      await Supabase.instance.client.from('complaints').update({
        'status': 'Open',
        'agent_justification': null,
        'history': {'events': events},
      }).eq('id', _currentComplaint['id']);

      await _refreshComplaint();
    });
  }

  // ======================================================
  //                     UI SECTION
  // ======================================================

  @override
  Widget build(BuildContext context) {
    final status = _currentComplaint['status'] ?? 'Open';

    /// 🔥 NEW RULE:
    /// User can edit anytime EXCEPT Resolved
    final isComplaintOwner =
        _currentComplaint['user_id'] ==
            Supabase.instance.client.auth.currentUser?.id;

    final canEdit = isComplaintOwner && status != 'Resolved';

    return Scaffold(
      appBar: AppBar(
        title: Text('complaint_details_section'.tr()),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
          onRefresh: _refreshComplaint,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildStatusHeader(),
                const SizedBox(height: 16),
                _buildBasicInfo(),
                const SizedBox(height: 16),
                _buildTimeline(),
                const SizedBox(height: 16),
                _buildComplaintDetails(),
                const SizedBox(height: 16),
                if (_currentComplaint['attachment_url'] != null)
                  _buildAttachment(),
                const SizedBox(height: 16),
                _buildActions(canEdit),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActions(bool canEdit) {
    final isComplaintOwner =
        _currentComplaint['user_id'] ==
            Supabase.instance.client.auth.currentUser?.id;

    final status = _currentComplaint['status'];

    final canAppeal =
        isComplaintOwner &&
            (status == 'Rejected' || status == 'Resolved');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_isActionLoading)
              const CircularProgressIndicator(),

            if (! _isActionLoading)
              if (canEdit)
                ElevatedButton.icon(
                  onPressed: _editComplaint,
                  icon: const Icon(Icons.edit),
                  label: Text('edit_complaint'.tr()),
                )
              else if (canAppeal)
                ElevatedButton.icon(
                  onPressed: _appealComplaint,
                  icon: const Icon(Icons.undo),
                  label: Text('appeal_decision_btn'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                )
              else
                Text(
                  'no_actions'.tr(),
                  style: TextStyle(color: Colors.grey),
                ),

            if (isComplaintOwner) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _deleteComplaint,
                icon: const Icon(Icons.delete_forever),
                label: Text('delete_complaint'.tr()),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------
  //  (Remaining UI helper widgets stay unchanged)
  // ------------------------------------------------------

  Widget _buildStatusHeader() {
    final status = _currentComplaint['status'] ?? 'Unknown';
    final statusConfig = _getStatusConfig(status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(statusConfig['icon'], color: statusConfig['color'], size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status: $status',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: statusConfig['color'],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: ${_currentComplaint['id'] ?? 'N/A'}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildInfoRow('subject'.tr(), _currentComplaint['subject']),
            _buildInfoRow(
                'complainer'.tr(), _currentComplaint['complainer_user_name']),
            _buildInfoRow(
                'target'.tr(), _currentComplaint['target_user_name']),
            if (_currentComplaint['shipment_id'] != null)
              _buildInfoRow(
                  'shipment_id'.tr(), _currentComplaint['shipment_id']),
            _buildInfoRow(
              'created'.tr(),
              DateFormat("MMM dd, yyyy - hh:mm a")
                  .format(DateTime.parse(_currentComplaint['created_at'])),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label)),
          Expanded(
            child: Text(value?.toString() ?? "N/A"),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final history = _currentComplaint['history'] as Map?;
    final events = List<Map<String, dynamic>>.from(
      (history?['events'] ?? []),
    );

    if (events.isEmpty) {
      events.add({
        'type': 'created',
        'title': 'Complaint Filed',
        'description': 'Complaint submitted',
        'timestamp': _currentComplaint['created_at']
      });
    }

    events.sort(
          (a, b) => DateTime.parse(b['timestamp'])
          .compareTo(DateTime.parse(a['timestamp'])),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ...events.map((e) => _buildTimelineItem(e)),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem(Map<String, dynamic> event) {
    final color = _getColorForEvent(event['type']);
    final icon = _getIconForEvent(event['type']);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.2),
              child: Icon(icon, color: color),
            ),
            Container(height: 50, width: 2, color: Colors.grey.shade300),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event['title'] ?? ''),
              Text(event['description'] ?? '',
                  style: TextStyle(color: Colors.grey.shade700)),
              Text(
                DateFormat("MMM dd, yyyy - hh:mm a")
                    .format(DateTime.parse(event['timestamp'])),
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildComplaintDetails() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _currentComplaint['complaint'] ?? 'No details provided',
          style: TextStyle(height: 1.5),
        ),
      ),
    );
  }

  Widget _buildAttachment() {
    final url = _currentComplaint['attachment_url'];
    if (url == null) return SizedBox();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => _showImageDialog(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(url, height: 200, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            Image.network(imageUrl),
            IconButton(
              icon: Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showConfirmationDialog(
      String title, String content,
      {bool isDestructive = false}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            child: Text("cancel".tr()),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive ? Colors.red : Colors.green,
            ),
            child: Text("confirm".tr()),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showJustificationDialog(
      String title, String action, TextEditingController controller) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: "provide_justification".tr(),
          ),
        ),
        actions: [
          TextButton(
            child: Text("cancel".tr()),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            child: Text(action),
            onPressed: () {
              if (controller.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("justification_empty".tr()),
                    backgroundColor: Colors.orange,
                  ),
                );
              } else {
                Navigator.pop(context, true);
              }
            },
          )
        ],
      ),
    );
  }

  Map<String, dynamic> _getStatusConfig(String status) {
    switch (status) {
      case 'Open':
        return {'color': Colors.orange, 'icon': Icons.schedule};
      case 'Resolved':
        return {'color': Colors.green, 'icon': Icons.check_circle};
      case 'Rejected':
        return {'color': Colors.red, 'icon': Icons.cancel};
      default:
        return {'color': Colors.grey, 'icon': Icons.info};
    }
  }

  IconData _getIconForEvent(String type) {
    switch (type) {
      case 'resolved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      case 'appealed':
        return Icons.undo;
      default:
        return Icons.info;
    }
  }

  Color _getColorForEvent(String type) {
    switch (type) {
      case 'resolved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'appealed':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}