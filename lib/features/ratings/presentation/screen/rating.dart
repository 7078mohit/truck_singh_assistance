import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

class Rating extends StatefulWidget {
  final String shipmentId;
  const Rating({super.key, required this.shipmentId});

  @override
  State<Rating> createState() => _RatingState();
}

class _RatingState extends State<Rating> {
  String? currentUserName;
  String? currentUserRole;

  String? person1Name;
  String? person1Id;
  String? person1Role;
  double rating1 = 0;
  TextEditingController feedback1 = TextEditingController();

  String? person2Name;
  String? person2Id;
  String? person2Role;
  double rating2 = 0;
  TextEditingController feedback2 = TextEditingController();

  bool isLoading = true;
  final _client = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _fetchNames().then((_) => fetchExistingRating());
  }

  Future<int> submitRating({
    required String shipmentId,
    required String person1Id,
    required String person2Id,
    required double rating1,
    required double rating2,
    required String feedback1,
    required String feedback2,
  }) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) {
      throw Exception(tr("error_user_not_authenticated"));
    }

    final profileResponse = await _client
        .from('user_profiles')
        .select('role, custom_user_id')
        .eq('user_id', currentUser.id)
        .maybeSingle();

    if (profileResponse == null) {
      throw Exception(tr("error_user_profile_not_found"));
    }

    final currentUserRole =
    (profileResponse['role'] as String?)?.trim().toLowerCase();
    final currentUserCustomId = profileResponse['custom_user_id'] as String?;

    final shipmentResponse = await _client
        .from('shipment')
        .select('assigned_driver, assigned_agent, shipper_id, delivery_date')
        .eq('shipment_id', shipmentId)
        .maybeSingle();

    if (shipmentResponse == null) {
      throw Exception(tr("error_shipment_not_found"));
    }

    final deliveryDate =
    DateTime.tryParse(shipmentResponse['delivery_date'] ?? "");

    final isExpired = deliveryDate != null &&
        DateTime.now().isAfter(deliveryDate.add(const Duration(days: 7)));

    if (isExpired) throw Exception("ratingPeriodExpired".tr());

    final driverId = shipmentResponse['assigned_driver'] as String?;
    final assignedId = shipmentResponse['assigned_agent'] as String?;
    final shipperId = shipmentResponse['shipper_id'] as String?;

    final List<Map<String, dynamic>> toSubmit = [];

    // SAME LOGIC: null-safe
    switch (currentUserRole) {
      case 'shipper':
        if (driverId != null) {
          toSubmit.add({
            'shipment_id': shipmentId,
            'rater_id': currentUserCustomId,
            'ratee_id': driverId,
            'rater_role': 'Shipper',
            'ratee_role': 'Driver',
            'rating': rating1.round(),
            'feedback': feedback1.isNotEmpty ? feedback1 : null,
          });
        }
        if (assignedId != null && assignedId != shipperId) {
          toSubmit.add({
            'shipment_id': shipmentId,
            'rater_id': currentUserCustomId,
            'ratee_id': assignedId,
            'rater_role': 'Shipper',
            'ratee_role': 'Agent',
            'rating': rating2.round(),
            'feedback': feedback2.isNotEmpty ? feedback2 : null,
          });
        }
        break;

      case 'agent':
        if (driverId != null) {
          toSubmit.add({
            'shipment_id': shipmentId,
            'rater_id': currentUserCustomId,
            'ratee_id': driverId,
            'rater_role': 'Agent',
            'ratee_role': 'Driver',
            'rating': rating1.round(),
            'feedback': feedback1.isNotEmpty ? feedback1 : null,
          });
        }
        if (shipperId != null) {
          toSubmit.add({
            'shipment_id': shipmentId,
            'rater_id': currentUserCustomId,
            'ratee_id': shipperId,
            'rater_role': 'Agent',
            'ratee_role': 'Shipper',
            'rating': rating2.round(),
            'feedback': feedback2.isNotEmpty ? feedback2 : null,
          });
        }
        break;

      case 'truckowner':
        if (driverId != null) {
          toSubmit.add({
            'shipment_id': shipmentId,
            'rater_id': currentUserCustomId,
            'ratee_id': driverId,
            'rater_role': 'TruckOwner',
            'ratee_role': 'Driver',
            'rating': rating1.round(),
            'feedback': feedback1.isNotEmpty ? feedback1 : null,
          });
        }
        if (shipperId != null) {
          toSubmit.add({
            'shipment_id': shipmentId,
            'rater_id': currentUserCustomId,
            'ratee_id': shipperId,
            'rater_role': 'TruckOwner',
            'ratee_role': 'Shipper',
            'rating': rating2.round(),
            'feedback': feedback2.isNotEmpty ? feedback2 : null,
          });
        }
        break;

      case 'driver':
        if (shipperId != null) {
          toSubmit.add({
            'shipment_id': shipmentId,
            'rater_id': currentUserCustomId,
            'ratee_id': shipperId,
            'rater_role': 'Driver',
            'ratee_role': 'Shipper',
            'rating': rating1.round(),
            'feedback': feedback1.isNotEmpty ? feedback1 : null,
          });
        }
        if (assignedId != null) {
          toSubmit.add({
            'shipment_id': shipmentId,
            'rater_id': currentUserCustomId,
            'ratee_id': assignedId,
            'rater_role': 'Driver',
            'ratee_role': 'Agent',
            'rating': rating2.round(),
            'feedback': feedback2.isNotEmpty ? feedback2 : null,
          });
        }
        break;
    }

    if (toSubmit.isEmpty) {
      throw Exception(tr("error_no_ratings_to_submit"));
    }

    int finalEdit = 0;

    for (final r in toSubmit) {
      final existing = await _client
          .from('ratings')
          .select('edit_count')
          .eq('shipment_id', r['shipment_id'])
          .eq('rater_id', r['rater_id'])
          .eq('ratee_id', r['ratee_id'])
          .maybeSingle();

      final count = (existing?['edit_count'] as int? ?? 0) + 1;

      if (count > 3) throw Exception(tr("error_edit_limit_reached"));

      r['edit_count'] = count;
      finalEdit = count;

      await _client
          .from('ratings')
          .upsert(r, onConflict: 'shipment_id,rater_id,ratee_id')
          .select();
    }

    return finalEdit;
  }

  Future<void> _fetchNames() async {
    try {
      final currentUser = _client.auth.currentUser;
      if (currentUser == null) throw Exception(tr("error_no_logged_in_user"));

      final currentProfile = await _client
          .from('user_profiles')
          .select('custom_user_id, name, role')
          .eq('user_id', currentUser.id)
          .maybeSingle();

      currentUserName = currentProfile?['name'];
      currentUserRole =
          (currentProfile?['role'] as String?)?.trim().toLowerCase();

      final shipment = await _client
          .from('shipment')
          .select('shipper_id, assigned_driver, assigned_agent')
          .eq('shipment_id', widget.shipmentId)
          .maybeSingle();

      final shipperId = shipment?['shipper_id'];
      final driverId = shipment?['assigned_driver'];
      final agentId = shipment?['assigned_agent'];

      Future<String?> getName(String? id) async {
        if (id == null) return null;
        final res = await _client
            .from('user_profiles')
            .select('name')
            .eq('custom_user_id', id)
            .maybeSingle();
        return res?['name'];
      }

      final shipperName = await getName(shipperId);
      final driverName = await getName(driverId);
      final agentName = await getName(agentId);

      switch (currentUserRole) {
        case 'shipper':
          person1Name = driverName;
          person1Id = driverId;
          person1Role = tr("driver");

          if (agentId != shipperId) {
            person2Name = agentName;
            person2Id = agentId;
            person2Role = tr("agent");
          }
          break;

        case 'agent':
          person1Name = driverName;
          person1Id = driverId;
          person1Role = tr("driver");

          person2Name = shipperName;
          person2Id = shipperId;
          person2Role = tr("shipper");
          break;

        case 'truckowner':
          person1Name = driverName;
          person1Id = driverId;
          person1Role = tr("driver");

          person2Name = shipperName;
          person2Id = shipperId;
          person2Role = tr("shipper");
          break;

        case 'driver':
          person1Name = shipperName;
          person1Id = shipperId;
          person1Role = tr("shipper");

          if (agentId != shipperId) {
            person2Name = agentName;
            person2Id = agentId;
            person2Role = tr("agent");
          }
          break;
      }

      if (mounted) setState(() => isLoading = false);
    } catch (e) {
      debugPrint("Error _fetchNames: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> fetchExistingRating() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return;

      final profile = await _client
          .from('user_profiles')
          .select('custom_user_id')
          .eq('user_id', user.id)
          .maybeSingle();

      final customId = profile?['custom_user_id'];
      if (customId == null) return;

      final response = await _client
          .from('ratings')
          .select('ratee_id,rating,feedback')
          .eq('shipment_id', widget.shipmentId)
          .eq('rater_id', customId);

      for (final r in response) {
        final rateeId = r['ratee_id'];

        if (rateeId == person1Id) {
          rating1 = (r['rating'] ?? 0).toDouble();
          feedback1.text = r['feedback'] ?? "";
        } else if (rateeId == person2Id) {
          rating2 = (r['rating'] ?? 0).toDouble();
          feedback2.text = r['feedback'] ?? "";
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Error existing rating: $e");
    }
  }

  Widget shimmerBox(double h, double w) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        height: h,
        width: w,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget buildShimmerSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        shimmerBox(28, 200),
        const SizedBox(height: 20),
        shimmerBox(60, double.infinity),
        const SizedBox(height: 16),
        shimmerBox(24, 150),
      ],
    );
  }

  void _handleSubmitRating() async {
    try {
      final editCount = await submitRating(
        shipmentId: widget.shipmentId,
        person1Id: person1Id ?? "",
        person2Id: person2Id ?? "",
        rating1: rating1,
        rating2: rating2,
        feedback1: feedback1.text,
        feedback2: feedback2.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr("ratings_submitted_successfully"))),
        );
      }

      Navigator.pop(context, editCount);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${tr("error")}: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr("rate_shipment"))),
      body: isLoading
          ? buildShimmerSkeleton()
          : Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(
              "${tr('hello')} ${currentUserName ?? ''},",
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),
            Text(tr("please_rate_your_experience")),
            const Divider(height: 32),

            // PERSON 1
            if (person1Name != null) ...[
              Text(
                "${tr("rate")} $person1Name (${person1Role ?? ''})",
                style: const TextStyle(fontSize: 16),
              ),
              RatingBar.builder(
                initialRating: rating1,
                minRating: 1,
                itemBuilder: (_, __) =>
                const Icon(Icons.star, color: Colors.amber),
                onRatingUpdate: (r) => setState(() => rating1 = r),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: feedback1,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: "${tr("feedback_for")} $person1Name",
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 28),
            ],
            // PERSON 2
            if (person2Name != null) ...[
              Text(
                "${tr("rate")} $person2Name (${person2Role ?? ''})",
                style: const TextStyle(fontSize: 16),
              ),
              RatingBar.builder(
                initialRating: rating2,
                minRating: 1,
                itemBuilder: (_, __) =>
                const Icon(Icons.star, color: Colors.amber),
                onRatingUpdate: (r) => setState(() => rating2 = r),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: feedback2,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: "${tr("feedback_for")} $person2Name",
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 28),
            ],
            Center(
              child: FilledButton.icon(
                onPressed: _handleSubmitRating,
                icon: const Icon(Icons.send),
                label: Text(tr("submit_ratings")),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    feedback1.dispose();
    feedback2.dispose();
    super.dispose();
  }
}