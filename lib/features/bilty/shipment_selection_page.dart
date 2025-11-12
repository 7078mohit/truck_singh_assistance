import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:logistics_toolkit/config/theme.dart';
import 'package:logistics_toolkit/features/bilty/bilty_pdf_preview_screen.dart';
import 'package:logistics_toolkit/features/bilty/transport_bilty_form.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

enum PdfState { notDownloaded, downloaded }

class ShipmentSelectionPage extends StatefulWidget {
  const ShipmentSelectionPage({super.key});

  @override
  State<ShipmentSelectionPage> createState() => _ShipmentSelectionPageState();
}

class _ShipmentSelectionPageState extends State<ShipmentSelectionPage> {
  List<Map<String, dynamic>> shipments = [];
  Map<String, Map<String, dynamic>> biltyMap = {};
  Map<String, PdfState> biltyStates = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchShipmentsAndBilties();
  }

  Future<void> _fetchShipmentsAndBilties() async {
    setState(() {
      isLoading = true;
    });

    final customUserId = Supabase
        .instance
        .client
        .auth
        .currentUser
        ?.userMetadata?['custom_user_id'];
    if (customUserId == null) {
      shipments = [];
      biltyMap = {};
      biltyStates = {};
      setState(() => isLoading = false);
      return;
    }

    final shipmentResponse = await Supabase.instance.client
        .from('shipment')
        .select('shipment_id, pickup, drop, delivery_date')
        .eq('assigned_agent', customUserId)
        .order('created_at', ascending: false);

    shipments = List<Map<String, dynamic>>.from(shipmentResponse);

    biltyMap.clear();
    biltyStates.clear();
    for (var shipment in shipments) {
      final shipmentId = shipment['shipment_id'].toString();
      final bilty = await Supabase.instance.client
          .from('bilties')
          .select()
          .eq('shipment_id', shipmentId)
          .maybeSingle();
      if (bilty != null) {
        biltyMap[shipmentId] = Map<String, dynamic>.from(bilty);

        // Check if local PDF exists
        final appDir = await getApplicationDocumentsDirectory();
        final localPath = '${appDir.path}/$shipmentId.pdf';
        final file = File(localPath);
        biltyStates[shipmentId] =
        await file.exists() ? PdfState.downloaded : PdfState.notDownloaded;
      }
    }

    setState(() {
      isLoading = false;
    });
  }

  Future<void> _downloadBilty(Map<String, dynamic> bilty) async {
    final shipmentId = bilty['shipment_id'].toString();
    final filePathInStorage = bilty['file_path'];
    final publicUrl = Supabase.instance.client.storage
        .from('bilties')
        .getPublicUrl(filePathInStorage);

    final response = await http.get(Uri.parse(publicUrl));
    if (response.statusCode == 200) {
      final appDir = await getApplicationDocumentsDirectory();
      final localPath = '${appDir.path}/$shipmentId.pdf';
      final file = File(localPath);
      await file.writeAsBytes(response.bodyBytes, flush: true);

      biltyStates[shipmentId] = PdfState.downloaded;
      setState(() {});

      ScaffoldMessenger.of(context)
          .showSnackBar( SnackBar(content: Text('biltyPdfDownloaded'.tr())));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar( SnackBar(content: Text('couldNotDownloadBiltyPdf'.tr())));
    }
  }

  void _previewBilty(String shipmentId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final localPath = '${appDir.path}/$shipmentId.pdf';
    final file = File(localPath);

    if (await file.exists()) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BiltyPdfPreviewScreen(localPath: localPath),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('biltyPdfNotFound'.tr()),
        ),
      );
    }
  }

  Future<void> _shareBilty(Map<String, dynamic> shipment) async {
    final shipmentId = shipment['shipment_id'].toString();
    final appDir = await getApplicationDocumentsDirectory();
    final localPath = '${appDir.path}/$shipmentId.pdf';
    final file = File(localPath);

    if (await file.exists()) {
      try {
        await Share.shareXFiles([XFile(localPath)],
            text: "Here is the Bilty for Shipment #$shipmentId");
      } catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error sharing bilty: $e")));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("pleaseDownloadBeforeSharing".tr()),
        ),
      );
    }
  }

  Future<void> _deleteBilty(Map<String, dynamic> shipment) async {
    final shipmentId = shipment['shipment_id'].toString();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title:  Text('deleteBilty'.tr()),
        content:  Text('deleteBiltyConfirmation'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:  Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:  Text('delete'.tr(), style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final bilty = biltyMap[shipmentId];
      if (bilty == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar( SnackBar(content: Text('noBiltyFoundToDelete'.tr())));
        return;
      }

      final filePathInStorage = bilty['file_path'];
      if (filePathInStorage != null && filePathInStorage.isNotEmpty) {
        await Supabase.instance.client.storage.from('bilties').remove([
          filePathInStorage,
        ]);
      }

      await Supabase.instance.client
          .from('bilties')
          .delete()
          .eq('shipment_id', shipmentId);

      final appDir = await getApplicationDocumentsDirectory();
      final localPath = '${appDir.path}/$shipmentId.pdf';
      final localFile = File(localPath);
      if (await localFile.exists()) {
        await localFile.delete();
      }

      biltyMap.remove(shipmentId);
      biltyStates[shipmentId] = PdfState.notDownloaded;
      setState(() {});

      ScaffoldMessenger.of(context)
          .showSnackBar( SnackBar(content: Text('biltyDeletedSuccessfully'.tr())));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error deleting bilty: $e')));
    }
  }

  String trimAddress(String address) {
    String cleaned = address
        .replaceAll(RegExp(r'\b(At Post|Post|Tal|Taluka|Dist|District|Po)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    List<String> parts = cleaned.split(',');
    parts = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

    if (parts.length >= 3) {
      String first = parts[0];
      String city = parts[parts.length - 2];
      return "$first,$city";
    } else if (parts.length == 2) {
      return "${parts[0]}, ${parts[1]}";
    } else {
      return cleaned.length > 50 ? "${cleaned.substring(0, 50)}..." : cleaned;
    }
  }

  Future<void> _refreshShipments() async {
    await _fetchShipmentsAndBilties();
  }


// Newly Added a skeleton loader
  Widget buildSkeletonLoader() {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Card(
            elevation: 2,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey[300],
                radius: 20,
              ),
              title: Container(
                width: double.infinity,
                height: 16,
                color: Colors.grey[300],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Container(width: 100, height: 12, color: Colors.grey[300]),
                  const SizedBox(height: 4),
                  Container(width: 150, height: 12, color: Colors.grey[300]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title:  Text("selectShipmentForBilty".tr())),
      body:  SafeArea(
        child: isLoading
            ? buildSkeletonLoader()
            : RefreshIndicator(
          onRefresh: _refreshShipments,
          child: shipments.isEmpty
              ?  Center(child: Text("noShipmentsFound".tr()))
              : ListView.builder(
            itemCount: shipments.length,
            itemBuilder: (context, index) {
              final shipment = shipments[index];
              final shipmentIdStr = shipment['shipment_id'].toString();
              final bilty = biltyMap[shipmentIdStr];
              final state = biltyStates[shipmentIdStr] ?? PdfState.notDownloaded;

              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text(
                    "Shipment $shipmentIdStr",
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on, color: AppColors.teal, size: 20),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${trimAddress(shipment['pickup'] ?? '')}',
                              style: Theme.of(context).textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.flag, color: Colors.red, size: 20),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${trimAddress(shipment['drop'] ?? '')}',
                              style: Theme.of(context).textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Delivery: ${shipment['delivery_date'] ?? 'N/A'}",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      bilty == null
                          ? ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BiltyFormPage(shipmentId: shipmentIdStr),
                            ),
                          ).then((_) async {
                            final bilty = await Supabase.instance.client
                                .from('bilties')
                                .select()
                                .eq('shipment_id', shipmentIdStr)
                                .maybeSingle();

                            if (bilty != null) {
                              biltyMap[shipmentIdStr] = Map<String, dynamic>.from(bilty);

                              final appDir = await getApplicationDocumentsDirectory();
                              final localPath = '${appDir.path}/$shipmentIdStr.pdf';
                              final file = File(localPath);
                              biltyStates[shipmentIdStr] =
                              await file.exists() ? PdfState.downloaded : PdfState.notDownloaded;
                            }

                            setState(() {});
                          });
                        },
                        child:  Text("generateBilty".tr()),
                      )
                          : Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: state == PdfState.downloaded ? Colors.grey : null,
                            ),
                            onPressed: state == PdfState.downloaded ? null : () => _downloadBilty(bilty),
                            child: Text(state == PdfState.downloaded ? "downloaded".tr() : "downloadBilty".tr()),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.remove_red_eye),
                            onPressed: () => _previewBilty(shipmentIdStr),
                          ),
                          IconButton(
                            onPressed: state == PdfState.downloaded ? () => _shareBilty(bilty) : null,
                            icon: const Icon(Icons.share),
                          ),
                          IconButton(
                            onPressed: state == PdfState.downloaded ? () => _deleteBilty(bilty) : null,
                            icon: const Icon(Icons.delete),
                          ),
                        ],
                      ),
                    ],
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