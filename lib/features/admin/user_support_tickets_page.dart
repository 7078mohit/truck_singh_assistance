import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'support_ticket_detail_page.dart';
import 'support_ticket_submission_page.dart';

class UserSupportTicketsPage extends StatefulWidget {
  const UserSupportTicketsPage({super.key});

  @override
  State<UserSupportTicketsPage> createState() => _UserSupportTicketsPageState();
}

class _UserSupportTicketsPageState extends State<UserSupportTicketsPage> {
  late Future<List<Map<String, dynamic>>> _ticketsFuture;
  String _selectedFilter = 'All';
  final List<String> _filters = ['All'.tr(), 'Pending'.tr(), 'In Progress'.tr(), 'Resolved'.tr()];

  @override
  void initState() {
    super.initState();
    _ticketsFuture = _fetchUserTickets();
    setState(() {});
  }

  Future<List<Map<String, dynamic>>> _fetchUserTickets() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return [];

      PostgrestFilterBuilder query = Supabase.instance.client
          .from('support_tickets')
          .select()
          .eq('user_id', user.id);

      if (_selectedFilter != 'All') {
        query = query.eq('status', _selectedFilter);
      }

      final response = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _ticketsFuture = _fetchUserTickets();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:  Text("My Support Tickets".tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SupportTicketSubmissionPage(),
                ),
              );
              if (result == true) {
                _refresh();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildFilterChips(),
            Expanded(child: _buildTicketsList()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _filters.map((filter) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: FilterChip(
                label: Text(filter),
                selected: _selectedFilter == filter,
                onSelected: (selected) {
                  setState(() {
                    _selectedFilter = filter;
                    _ticketsFuture = _fetchUserTickets();
                  });
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTicketsList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _ticketsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text("Error: ${snapshot.error}"),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _refresh, child:  Text('Retry'.tr())),
              ],
            ),
          );
        }

        final tickets = snapshot.data!;

        if (tickets.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.support_agent_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  _selectedFilter == 'All'
                      ? "No support tickets found".tr()
                      : "No $_selectedFilter tickets found",
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  "Tap the + button to create a new support request".tr(),
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                        const SupportTicketSubmissionPage(),
                      ),
                    );
                    if (result == true) {
                      _refresh();
                    }
                  },
                  icon: const Icon(Icons.add),
                  label:  Text('Create Support Request'.tr()),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            itemCount: tickets.length,
            itemBuilder: (context, index) {
              final ticket = tickets[index];
              return _buildTicketCard(ticket);
            },
          ),
        );
      },
    );
  }

  Widget _buildTicketCard(Map<String, dynamic> ticket) {
    final createdAt = DateTime.parse(ticket['created_at']);
    final updatedAt = ticket['updated_at'] != null
        ? DateTime.parse(ticket['updated_at'])
        : createdAt;
    final status = ticket['status'] ?? 'Pending';
    final priority = ticket['priority'] ?? 'Medium';

    return Card(
      color: Theme.of(context).cardColor,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  EnhancedSupportTicketDetailPage(ticket: ticket),
            ),
          );
          if (result == true) {
            _refresh();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticket['subject'] ?? 'No Subject'.tr(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _getStatusColor(status)),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: _getStatusColor(status),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                ticket['message'] ?? '',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _getPriorityColor(priority),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    priority,
                    style: TextStyle(
                      color: _getPriorityColor(priority),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('dd MMM, hh:mm a').format(createdAt),
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  const Spacer(),
                  if (updatedAt.isAfter(createdAt)) ...[
                    Icon(Icons.update, size: 14, color: Colors.blue[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Updated ${DateFormat('dd MMM').format(updatedAt)}',
                      style: TextStyle(
                        color: Colors.blue[600],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
              if (ticket['screenshot_url'] != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.image, size: 14, color: Colors.green[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Has screenshot'.tr(),
                      style: TextStyle(color: Colors.green[600], fontSize: 12),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Pending':
        return Colors.orange;
      case 'In Progress':
        return Colors.blue;
      case 'Resolved':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'Low':
        return Colors.green;
      case 'Medium':
        return Colors.orange;
      case 'High':
        return Colors.red;
      case 'Urgent':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}