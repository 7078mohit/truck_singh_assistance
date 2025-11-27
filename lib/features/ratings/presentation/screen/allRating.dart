import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class TripRatingsPage1 extends StatelessWidget {
  final List<Map<String, dynamic>> trips = [
    {
      'tripId': 'SHP-20250612-0006',
      'shipper': 'ABC Logistics',
      'from': 'Mumbai',
      'to': 'Pune',
      'rating': 5,
      'Date': '12/06/2025',
      'feedback': 'Smooth delivery and professional driver.',
    },
    {
      'tripId': 'SHP-20250612-0002',
      'shipper': 'QuickShip Pvt Ltd',
      'from': 'Delhi',
      'to': 'Chandigarh',
      'rating': 4,
      'Date': '12/05/2025',
      'feedback': 'Good service but arrived slightly late.',
    },
    {
      'tripId': 'SHP-20250612-0003',
      'shipper': 'Mega Movers',
      'from': 'Bangalore',
      'to': 'Hyderabad',
      'rating': 3,
      'Date': '12/04/2025',
      'feedback': 'Driver was polite but vehicle needed maintenance.',
    },
  ];

  void showTripDetailsPopup(BuildContext context, Map<String, dynamic> trip) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'trip_details'.tr(),
          style: const TextStyle(color: Colors.blueAccent),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rowWithIcon(
                Icons.numbers,
                'trip_id'.tr(),
                trip['tripId'] ?? '',
              ),
              const SizedBox(height: 8),
              _rowWithIcon(
                Icons.local_shipping,
                'shipper'.tr(),
                trip['shipper'] ?? '',
              ),
              const SizedBox(height: 8),
              _rowWithIcon(
                Icons.date_range,
                'date'.tr(),
                trip['Date'] ?? '',
              ),
              const SizedBox(height: 8),
              _rowWithIcon(
                Icons.route,
                'route'.tr(),
                '${trip['from']} → ${trip['to']}',
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  const Icon(Icons.feedback,
                      color: Colors.blueAccent, size: 20),
                  const SizedBox(width: 5),
                  Text(
                    'feedback'.tr(),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),

              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  trip['feedback'] ?? '',
                  style: const TextStyle(color: Colors.black87, fontSize: 15),
                ),
              ),

              const Divider(),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return Icon(
                    i < (trip['rating'] ?? 0)
                        ? Icons.star
                        : Icons.star_border,
                    color: Colors.amber,
                    size: 28,
                  );
                }),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            onPressed: () => Navigator.pop(context),
            child: Text(
              'close'.tr(),
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ================== Styled Info Row ==================
  static Widget _rowWithIcon(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueAccent, size: 20),
        const SizedBox(width: 6),
        Expanded(child: infoRow(label, value)),
      ],
    );
  }

  static Widget infoRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87, fontSize: 16),
        children: [
          TextSpan(
            text: "$label: ",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('my_performance'.tr()),
        backgroundColor: Colors.blueAccent,
      ),
      body: ListView.builder(
        itemCount: trips.length + 1,
        itemBuilder: (context, index) {
          // First Card = Summary Card
          if (index == 0) {
            final avgRating = trips
                .map((e) => (e['rating'] as int?) ?? 0)
                .reduce((a, b) => a + b) /
                trips.length;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "overall_performance".tr(),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text("average_rating".tr(),
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 4),
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                      Text(avgRating.toStringAsFixed(1),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Text(
                    "total_trips".tr(args: [trips.length.toString()]),
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "tap_trip_feedback".tr(),
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ],
              ),
            );
          }

          final trip = trips[index - 1];

          return GestureDetector(
            onTap: () => showTripDetailsPopup(context, trip),
            child: Card(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              elevation: 3,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: Text(
                        trip['tripId'] ?? '',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                    const SizedBox(height: 4),

                    Row(
                      children: [
                        const Icon(Icons.local_shipping,
                            color: Colors.blueAccent, size: 20),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            "${'shipper'.tr()}: ${trip['shipper'] ?? ''}",
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.my_location,
                            color: Colors.blueAccent, size: 20),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            "${'origin'.tr()}: ${trip['from'] ?? ''}",
                            style: const TextStyle(
                                fontSize: 15, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            color: Colors.blueAccent, size: 20),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            "${'destination'.tr()}: ${trip['to'] ?? ''}",
                            style: const TextStyle(
                                fontSize: 15, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.date_range,
                            color: Colors.blueAccent, size: 20),
                        const SizedBox(width: 5),
                        Text(
                          "${'date'.tr()}: ${trip['Date'] ?? ''}",
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey[800]),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),
                    Row(
                      children: List.generate(5, (i) {
                        return Icon(
                          i < (trip['rating'] ?? 0)
                              ? Icons.star
                              : Icons.star_border,
                          color: Colors.amber,
                          size: 22,
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}