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
  bool canRate = true;
  final _client = Supabase.instance.client;

  //Submit rating part below
  Future<int> submitRating({
    required String shipmentId,
    required String person1Id,
    required String person2Id,
    required double rating1,
    required double rating2,
    required String feedback1,
    required String feedback2,
  }) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) {
      throw Exception(tr("error_user_not_authenticated"));
    }

    final profileResponse = await _client
        .from('user_profiles')
        .select('role, custom_user_id')
        .eq('user_id', currentUserId)
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

    final deliveryDate = DateTime.tryParse(
      shipmentResponse['delivery_date'] ?? '',
    );

    final bool isRatingPeriodExpired =
        deliveryDate != null &&
            DateTime.now().isAfter(deliveryDate.add(const Duration(days: 7)));

    if (isRatingPeriodExpired) {
      throw Exception('ratingPeriodExpired'.tr());
    }

    final driverId = shipmentResponse['assigned_driver'] as String?;
    final assignedId = shipmentResponse['assigned_agent'] as String?;
    final shipperId = shipmentResponse['shipper_id'] as String?;

    final List<Map<String, dynamic>> ratingsToSubmit = [];

    switch (currentUserRole) {
      case 'shipper':
        if (driverId != null) {
          ratingsToSubmit.add({
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
          ratingsToSubmit.add({
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
          ratingsToSubmit.add({
            'shipment_id': shipmentId,
            'rater_id': currentUserCustomId,
            'ratee_id': driverId,
            'rater_role': 'Shipper',
            'ratee_role': 'Driver',
            'rating': rating1.round(),
            'feedback': feedback1.isNotEmpty ? feedback1 : null,
          });
        }
        if (shipperId != null && shipperId != assignedId) {
          ratingsToSubmit.add({
            'shipment_id': shipmentId,
            'rater_id': currentUserCustomId,
            'ratee_id': shipperId,
            'rater_role': 'Agent',
            'ratee_role': 'Shipper',
            'rating': rating1.round(),
            'feedback': feedback1.isNotEmpty ? feedback1 : null,
          });
        }
        break;
      case 'truckowner':
        if (driverId != null) {
          ratingsToSubmit.add({
            'shipment_id': shipmentId,
            'rater_id': currentUserCustomId,
            'ratee_id': driverId,
            'rater_role': 'Shipper',
            'ratee_role': 'Driver',
            'rating': rating1.round(),
            'feedback': feedback1.isNotEmpty ? feedback1 : null,
          });
        }
        if (shipperId != null && shipperId != assignedId) {
          ratingsToSubmit.add({
            'shipment_id': shipmentId,
            'rater_id': currentUserCustomId,
            'ratee_id': shipperId,
            'rater_role': 'Agent',
            'ratee_role': 'Shipper',
            'rating': rating1.round(),
            'feedback': feedback1.isNotEmpty ? feedback1 : null,
          });
        }
        break;
      case 'driver':
        if (shipperId != null) {
          ratingsToSubmit.add({
            'shipment_id': shipmentId,
            'rater_id': currentUserCustomId,
            'ratee_id': shipperId,
            'rater_role': 'Driver',
            'ratee_role': 'Shipper',
            'rating': rating1.round(),
            'feedback': feedback1.isNotEmpty ? feedback1 : null,
          });
        }
        if (assignedId != null && assignedId != shipperId) {
          ratingsToSubmit.add({
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
      default:
        throw Exception("${tr("error_invalid_role")}: $currentUserRole");
    }

    if (ratingsToSubmit.isEmpty) {
      throw Exception(tr("error_no_ratings_to_submit"));
    }

    int finalEditCount = 0;
    for (final rating in ratingsToSubmit) {
      final existingRating = await _client
          .from('ratings')
          .select('edit_count')
          .eq('shipment_id', rating['shipment_id'])
          .eq('rater_id', rating['rater_id'])
          .eq('ratee_id', rating['ratee_id'])
          .maybeSingle();

      int currentEditCount = existingRating?['edit_count'] as int? ?? 0;

      final newEditCount = currentEditCount + 1;
      finalEditCount = newEditCount;

      if (newEditCount > 3) {
        throw Exception(tr("error_edit_limit_reached"));
      }

      rating['edit_count'] = newEditCount;

      final upsertResponse = await _client
          .from('ratings')
          .upsert(rating, onConflict: 'shipment_id, rater_id, ratee_id')
          .select();

      debugPrint("Upsert result: $upsertResponse");
    }

    return finalEditCount;
  }

  @override
  void initState() {
    super.initState();
    _fetchNames().then((_) {
      fetchExistingRating();
    });
  }
  Future<void> _fetchNames() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception(tr("error_no_logged_in_user"));
      final currentProfile = await _client
          .from('user_profiles')
          .select('custom_user_id, name, role')
          .eq('user_id', userId)
          .single();
      currentUserName = currentProfile['name'];
      currentUserRole = (currentProfile['role'] as String?)?.trim().toLowerCase();
      final currentUserCustomId = currentProfile['custom_user_id'];
      final shipment = await _client
          .from('shipment')
          .select('shipper_id, assigned_driver, assigned_agent')
          .eq('shipment_id', widget.shipmentId)
          .single();
      final shipperId = shipment['shipper_id'] as String?;
      final driverId = shipment['assigned_driver'] as String?;
      final assignedId = shipment['assigned_agent'] as String?;
      Future<String?> getName(String? id) async {
        if (id == null) return null;
        final profile = await _client
            .from('user_profiles')
            .select('name')
            .eq('custom_user_id', id)
            .maybeSingle();
        return profile?['name'];
      }
      final shipperName = await getName(shipperId);
      final driverName = await getName(driverId);
      final assignedName = await getName(assignedId);
      switch (currentUserRole) {
        case 'shipper':
          person1Name = driverName;
          person1Id = driverId;
          person1Role = tr('driver');
          if (assignedId != null && assignedId != currentUserCustomId) {
            person2Name = assignedName;
            person2Id = assignedId;
            person2Role = tr('agent');
          }
          break;

        case 'agent':
          person1Name = driverName;
          person1Id = driverId;
          person1Role = tr('driver');
          if (shipperId != null && shipperId != currentUserCustomId) {
            person2Name = shipperName;
            person2Id = shipperId;
            person2Role = tr('shipper');
          }
          break;

        case 'truckowner':
          person1Name = driverName;
          person1Id = driverId;
          person1Role = tr('driver');
          if (shipperId != null && shipperId != currentUserCustomId) {
            person2Name = shipperName;
            person2Id = shipperId;
            person2Role = tr('shipper');
          }
          break;

        case 'driver':
          person1Name = shipperName;
          person1Id = shipperId;
          person1Role = tr('shipper');
          if (assignedId != null && assignedId != shipperId) {
            person2Name = assignedName;
            person2Id = assignedId;
            person2Role = tr('agent');
          }
          break;
      }

      setState(() => isLoading = false);
    } catch (e) {
      debugPrint("Error fetching names: $e");
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> fetchExistingRating() async {
    try {
      final currentUserId = _client.auth.currentUser?.id;
      if (currentUserId == null) return;

      final profile = await _client
          .from('user_profiles')
          .select('custom_user_id')
          .eq('user_id', currentUserId)
          .maybeSingle();

      if (profile == null) return;
      final currentUserCustomId = profile['custom_user_id'];

      final shipmentResponse = await _client
          .from('shipment')
          .select('assigned_driver, assigned_agent, shipper_id, delivery_date')
          .eq('shipment_id', widget.shipmentId)
          .maybeSingle();

      final deliveryDate = DateTime.tryParse(
        shipmentResponse?['delivery_date'] ?? '',
      );

      canRate = deliveryDate != null &&
          !DateTime.now().isAfter(deliveryDate.add(const Duration(days: 7)));

      final existingRatings = await _client
          .from('ratings')
          .select('ratee_id,rating,feedback,edit_count')
          .eq('shipment_id', widget.shipmentId)
          .eq('rater_id', currentUserCustomId);

      for (var r in existingRatings) {
        if (r['ratee_id'] == person1Id) {
          rating1 = (r['rating'] as num?)?.toDouble() ?? 0;
          feedback1.text = r['feedback'] ?? '';
        } else if (r['ratee_id'] == person2Id) {
          rating2 = (r['rating'] as num?)?.toDouble() ?? 0;
          feedback2.text = r['feedback'] ?? '';
        }
        if(r['edit_count'] > 3) {
          canRate = false;
        }
      }
      setState(() {});
    } catch (e) {
      debugPrint("Error fetching existing ratings: $e");
    }
  }

  void _handleSubmitRating() async {
    try {
      final updatedEditCount = await submitRating(
        shipmentId: widget.shipmentId,
        person1Id: person1Id ?? '',
        person2Id: person2Id ?? '',
        rating1: rating1,
        rating2: rating2,
        feedback1: feedback1.text,
        feedback2: feedback2.text,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr("ratings_submitted_successfully"))),
      );
      Navigator.pop(context, updatedEditCount);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${tr("error")}: $e')));
    }
  }

  Widget buildShimmerSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(20.0),
      children: [
        shimmerBox(
          height: 28,
          width: 200,
          margin: const EdgeInsets.only(bottom: 18),
        ),
        shimmerBox(
          height: 60,
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
        ),
        const SizedBox(height: 10),
        shimmerBox(
          height: 20,
          width: 150,
          margin: const EdgeInsets.only(bottom: 8),
        ),
        shimmerStars(),
        shimmerBox(
          height: 70,
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 24),
        ),
        const SizedBox(height: 20),
        shimmerBox(
          height: 20,
          width: 150,
          margin: const EdgeInsets.only(bottom: 8),
        ),
        shimmerStars(),
        shimmerBox(
          height: 70,
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 24),
        ),
        const SizedBox(height: 10),
        shimmerBox(
          height: 48,
          width: double.infinity,
          margin: EdgeInsets.zero,
          borderRadius: 24,
        ),
      ],
    );
  }

  Widget shimmerBox({
    required double height,
    required double width,
    required EdgeInsets margin,
    double borderRadius = 8.0,
  }) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        height: height,
        width: width,
        margin: margin,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }

  Widget shimmerStars() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: List.generate(5, (_) {
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: shimmerBox(
              height: 24,
              width: 24,
              margin: EdgeInsets.zero,
              borderRadius: 12,
            ),
          );
        }),
      ),
    );
  }

  @override
  void dispose() {
    feedback1.dispose();
    feedback2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(tr("rate_shipment"))),
        body: buildShimmerSkeleton(),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr("rate_shipment"))),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Text(
              "${"hello".tr()} ${currentUserName ?? ''},",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text("please_rate_your_experience".tr()),
            const Divider(height: 30),
            if (person1Name != null) ...[
              Text("${tr("rate")} ${person1Name!} (${person1Role!})",
                  style: const TextStyle(fontSize: 16)),
              RatingBar.builder(
                initialRating: rating1,
                minRating: 1,
                itemBuilder: (context, _) => const Icon(Icons.star, color: Colors.amber),
                onRatingUpdate: (rating) => setState(() => rating1 = rating),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: feedback1,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: "${'feedback_for'.tr() + person1Name!}",
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (person2Name != null) ...[
              Text("${tr("rate")} ${person2Name!} (${person2Role!})",
                  style: const TextStyle(fontSize: 16)),
              RatingBar.builder(
                initialRating: rating2,
                minRating: 1,
                itemBuilder: (context, _) => const Icon(Icons.star, color: Colors.amber),
                onRatingUpdate: (rating) => setState(() => rating2 = rating),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: feedback2,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: "${tr("feedback_for")} ${person2Name!}",
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 30),
            ],
            Center(
              child: ElevatedButton.icon(
                onPressed: canRate ?
                _handleSubmitRating
                    : () {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('${tr("rating_expired")}')));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: canRate ? Colors.orange : Colors.grey,
                  foregroundColor: canRate ? Colors.white : Colors.white70,
                ),
                icon: const Icon(Icons.send),
                label: Text(tr("submit_ratings")),
              ),
            ),
          ],
        ),
      ),
    );
  }
}