import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart' as ptr;
import 'package:easy_localization/easy_localization.dart';

import '../../../../config/theme.dart';

class TripRatingsPage extends StatefulWidget {
  const TripRatingsPage({super.key});

  @override
  State<TripRatingsPage> createState() => _TripRatingsPageState();
}

class _TripRatingsPageState extends State<TripRatingsPage> {
  final ptr.RefreshController _refreshController = ptr.RefreshController();
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _ratings = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchRatings();
  }

  String trimAddress(String address) {
    // Remove common redundant words
    String cleaned = address
        .replaceAll(
      RegExp(
        r'\b(At Post|Post|Tal|Taluka|Dist|District|Po)\b',
        caseSensitive: false,
      ),
      '',
    )
        .replaceAll(RegExp(r'\s+'), ' ') // normalize spaces
        .trim();

    List<String> parts = cleaned.split(',');
    parts = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

    if (parts.length >= 3) {
      String first = parts[0]; // village/area
      String city = parts[parts.length - 2];
      return "$first,$city";
    } else if (parts.length == 2) {
      return "${parts[0]}, ${parts[1]}";
    } else {
      // fallback: just shorten
      return cleaned.length > 50 ? "${cleaned.substring(0, 50)}..." : cleaned;
    }
  }

  Future<void> _fetchRatings() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception(tr("error_user_not_authenticated"));

      // Get custom_user_id
      final profile = await supabase
          .from('user_profiles')
          .select('custom_user_id')
          .eq('user_id', userId)
          .maybeSingle();

      if (profile == null) {
        throw Exception(tr("error_user_profile_not_found"));
      }

      final customUserId = profile['custom_user_id'] as String?;

      // Fetch ratings with shipment + raw rater IDs
      final response = await supabase
          .from('view_user_ratings')
          .select('*, shipment:shipment(shipment_id, pickup, drop, assigned_agent, assigned_driver, shipper_id)')
          .eq('ratee_id', customUserId!);

      final List<Map<String, dynamic>> tempRatings = [];

      for (final r in response) {
        final shipment = r['shipment'];
        final raterId = r['rater_id'] as String?;
        String? raterName;
        String? raterRole;

        if (raterId != null) {
          // Determine role based on match
          if (shipment['assigned_agent'] == raterId) {
            raterRole = "Agent";
          } else if (shipment['assigned_driver'] == raterId) {
            raterRole = "Driver";
          } else if (shipment['shipper_id'] == raterId) {
            raterRole = "Shipper";
          }

          // Lookup name
          final user = await supabase
              .from('user_profiles')
              .select('name')
              .eq('custom_user_id', raterId)
              .maybeSingle();
          raterName = user?['name'];
        }

        tempRatings.add({
          ...r,
          'pickup': trimAddress(shipment['pickup'] ?? ''),
          'drop': trimAddress(shipment['drop'] ?? ''),
          'rater_name': raterName ?? tr("na"),
          'rater_role': raterRole ?? tr("na"),
        });
      }

      if (mounted) {
        setState(() {
          _ratings = tempRatings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }


  void _showTripDetailsPopup(BuildContext context, Map<String, dynamic> trip) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Center(
                    child: Text(
                      tr("trip_details"),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      const SizedBox(width: 8),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _popupInfoCard(
                    Icons.numbers,
                    tr("trip_id"),
                    trip['shipment_id'],
                  ),
                  const SizedBox(height: 8),
                  _popupInfoCard(
                    Icons.person,
                    tr("shipper"),
                    trip['rater_name'] ?? tr("na"),
                  ),
                  const SizedBox(height: 8),
                  _popupInfoCard(
                    Icons.location_on,
                    tr("pickup"),
                    trip['pickup'],
                  ),
                  const SizedBox(height: 8),
                  _popupInfoCard(Icons.flag, tr("drop"), trip['drop']),
                  const SizedBox(height: 16),

                  // Feedback
                  Text(
                    tr("feedback"),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      trip['feedback'] ?? tr("no_feedback"),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: RatingBarIndicator(
                      rating: (trip['rating'] ?? 0).toDouble(),
                      itemBuilder: (context, _) =>
                      const Icon(Icons.star, color: Colors.amber),
                      itemCount: 5,
                      itemSize: 20,
                    ),
                  ),
                  // Close Button
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        tr("close"),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _popupInfoCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.orange.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: AppColors.orange),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black, fontSize: 14),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).primaryColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyLarge,
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    if (_ratings.isEmpty) return const SizedBox.shrink();

    final double avgRating =
        _ratings.map((r) => r['rating'] as int).reduce((a, b) => a + b) /
            _ratings.length;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr("overall_performance"),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  tr("average_rating"),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(width: 5),
                Text(
                  avgRating.toStringAsFixed(1),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 4),
                RatingBarIndicator(
                  rating: avgRating,
                  itemBuilder: (context, _) =>
                  const Icon(Icons.star, color: Colors.amber),
                  itemCount: 5,
                  itemSize: 20.0,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "${tr("total_trips_rated")}: ${_ratings.length}",
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr("my_performance"))),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? Center(
          child: Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red),
          ),
        )
            : ptr.SmartRefresher(
          controller: _refreshController,
          onRefresh: _fetchRatings,
          header: const ptr.WaterDropHeader(),
          child: ListView.builder(
            itemCount: _ratings.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return _buildSummaryCard();

              final trip = _ratings[index - 1];

              return InkWell(
                onTap: () => _showTripDetailsPopup(context, trip),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  margin: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Row : ID
                        Text(
                          trip['shipment_id'] ?? 'Unknown',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Completed Date
                        if (trip['delivery_date'] != null &&
                            trip['delivery_date'] != '')
                          Text(
                            "completed : ${trip['delivery_date']}".tr(),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                        const SizedBox(height: 8),

                        // Pickup Address
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: Colors.blue,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'PICKUP: ${trimAddress(trip['pickup'] ?? '')}',
                                style: const TextStyle(fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Drop Address
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.flag,
                              color: Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'DROP: ${trimAddress(trip['drop'] ?? '')}',
                                style: const TextStyle(fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),
                        // Rating Bar
                        RatingBarIndicator(
                          rating: (trip['rating'] ?? 0).toDouble(),
                          itemBuilder: (context, _) =>
                          const Icon(Icons.star, color: Colors.amber),
                          itemCount: 5,
                          itemSize: 20.0,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}