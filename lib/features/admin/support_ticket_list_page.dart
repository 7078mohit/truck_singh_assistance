import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'support_ticket_detail_page.dart';

class SupportTicketListPage extends StatefulWidget {
  const SupportTicketListPage({Key? key}) : super(key: key);

  @override
  State<SupportTicketListPage> createState() => _SupportTicketListPageState();
}

class _SupportTicketListPageState extends State<SupportTicketListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _tabs = ['Pending', 'In Progress', 'Resolved'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("support_tickets".tr()),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          tabs: _tabs.map((s) => Tab(text: s.tr())).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((s) => TicketList(status: s)).toList(),
      ),
    );
  }
}

class TicketList extends StatefulWidget {
  final String status;
  const TicketList({Key? key, required this.status}) : super(key: key);
  @override
  State<TicketList> createState() => _TicketListState();
}

class _TicketListState extends State<TicketList> {
  late Future<List<Map<String, dynamic>>> _ticketsFuture;

  @override
  void initState() {
    super.initState();
    _ticketsFuture = _fetchTickets();
  }

  Future<List<Map<String, dynamic>>> _fetchTickets() async {
    final res = await Supabase.instance.client
        .from('support_tickets')
        .select()
        .eq('status', widget.status)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  void _refresh() => setState(() => _ticketsFuture = _fetchTickets());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _ticketsFuture,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text("Error: ${snap.error}"));
        }

        final tickets = snap.data ?? [];

        if (tickets.isEmpty) {
          return Center(
            child: Text(
              "No ${widget.status.toLowerCase()} tickets found.",
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            itemCount: tickets.length,
            itemBuilder: (_, i) {
              final t = tickets[i];
              final created = DateTime.parse(t['created_at']);

              return Card(
                color: Theme.of(context).cardColor,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.support_agent, color: Colors.teal),
                  title: Text(t['user_name'] ?? 'N/A',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    t['message'],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(DateFormat('dd MMM, hh:mm a').format(created)),
                  onTap: () async {
                    final changed = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            EnhancedSupportTicketDetailPage(ticket: t),
                      ),
                    );
                    if (changed == true) _refresh();
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}