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

  final _filters = ['All', 'Pending', 'In Progress', 'Resolved'];

  @override
  void initState() {
    super.initState();
    _ticketsFuture = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    var query = Supabase.instance.client
        .from('support_tickets')
        .select()
        .eq('user_id', user.id);

    if (_selectedFilter != 'All') query = query.eq('status', _selectedFilter);

    final res =
    await query.order('created_at', ascending: false) as List<dynamic>;

    return List<Map<String, dynamic>>.from(res);
  }

  void _refreshNow() =>
      setState(() => _ticketsFuture = _fetch());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("My Support Tickets".tr()),
        actions: [
          IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SupportTicketSubmissionPage()),
                );
                if (result == true) _refreshNow();
              })
        ],
      ),
      body: Column(
        children: [
          _filterChips(),
          Expanded(child: _ticketList()),
        ],
      ),
    );
  }

  Widget _filterChips() => SizedBox(
    height: 50,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8),
      children: _filters
          .map((f) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FilterChip(
          label: Text(f.tr()),
          selected: _selectedFilter == f,
          onSelected: (_) {
            setState(() => _selectedFilter = f);
            _refreshNow();
          },
        ),
      ))
          .toList(),
    ),
  );

  Widget _ticketList() {
    return FutureBuilder(
      future: _ticketsFuture,
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _error(snapshot.error.toString());
        }

        final list = snapshot.data ?? [];

        if (list.isEmpty) return _empty();

        return RefreshIndicator(
          onRefresh: () async => _refreshNow(),
          child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => _ticketCard(list[i])),
        );
      },
    );
  }

  Widget _error(String msg) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 64, color: Colors.red),
        const SizedBox(height: 16),
        Text(msg),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _refreshNow, child: Text("Retry".tr())),
      ],
    ),
  );

  Widget _empty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.support_agent_outlined,
            size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text("No tickets found".tr(),
            style: const TextStyle(fontSize: 18, color: Colors.grey)),
        const SizedBox(height: 8),
        Text("Tap + to create a support request".tr(),
            style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () async {
            final res = await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SupportTicketSubmissionPage()));
            if (res == true) _refreshNow();
          },
          icon: const Icon(Icons.add),
          label: Text("Create Support Request".tr()),
        ),
      ],
    ),
  );

  Widget _ticketCard(Map<String, dynamic> t) {
    final created = DateTime.parse(t['created_at']);
    final updated = t['updated_at'] != null
        ? DateTime.parse(t['updated_at'])
        : created;

    final status = t['status'];
    final priority = t['priority'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: () async {
          final res = await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => EnhancedSupportTicketDetailPage(ticket: t)));
          if (res == true) _refreshNow();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(t['subject'] ?? "No Subject".tr(),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
              _badge(status, _statusColor(status))
            ]),
            const SizedBox(height: 8),
            Text(t['message'] ?? "",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[600])),

            const SizedBox(height: 12),
            Row(children: [
              _priorityDot(priority),
              const SizedBox(width: 8),
              Text(priority,
                  style: TextStyle(
                      color: _priorityColor(priority),
                      fontWeight: FontWeight.w500)),
              const SizedBox(width: 16),
              Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(DateFormat('dd MMM, hh:mm a').format(created),
                  style:
                  TextStyle(color: Colors.grey[500], fontSize: 12)),
              const Spacer(),

              // Updated time
              if (updated.isAfter(created))
                Row(children: [
                  Icon(Icons.update, size: 14, color: Colors.blue[600]),
                  const SizedBox(width: 4),
                  Text("Updated ${DateFormat('dd MMM').format(updated)}",
                      style: TextStyle(
                          color: Colors.blue[600],
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ]),
            ]),

            if (t['screenshot_url'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.image, size: 14, color: Colors.green[600]),
                  const SizedBox(width: 4),
                  Text("Has screenshot".tr(),
                      style:
                      TextStyle(fontSize: 12, color: Colors.green[600])),
                ]),
              )
          ]),
        ),
      ),
    );
  }

  Widget _badge(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: c.withOpacity(0.1),
        border: Border.all(color: c)),
    child: Text(t,
        style: TextStyle(color: c, fontWeight: FontWeight.w500)),
  );

  Widget _priorityDot(String p) => Container(
    width: 8,
    height: 8,
    decoration:
    BoxDecoration(shape: BoxShape.circle, color: _priorityColor(p)),
  );

  Color _statusColor(String s) {
    switch (s) {
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

  Color _priorityColor(String p) {
    switch (p) {
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