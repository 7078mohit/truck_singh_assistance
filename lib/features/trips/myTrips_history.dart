import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart' as ptr;
import 'package:path_provider/path_provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:share_plus/share_plus.dart';
import '../auth/model/address_model.dart';
import '../invoice/services/invoice_pdf_service.dart';
import 'myTrips_Services.dart';
import 'shipment_card.dart' as shipment_card;
import 'package:easy_localization/easy_localization.dart';


enum TaxType { withinState, outsideState }

class MyTripsHistory extends StatefulWidget {
  const MyTripsHistory({super.key});

  @override
  State<MyTripsHistory> createState() => _MyTripsHistoryPageState();
}

class _MyTripsHistoryPageState extends State<MyTripsHistory> {
  // Shipment, filter, and cached state
  List<Map<String, dynamic>> shipments = [];
  List<Map<String, dynamic>> filteredShipments = [];
  String? customUserId;
  String? role;
  String? selectedMonth;

  Set<String> ratedShipments = {};
  Map<String, int> ratingEditCount = {};
  bool loading = true;
  String searchQuery = '';
  String statusFilter = 'All';

  final ptr.RefreshController _refreshController = ptr.RefreshController(
    initialRefresh: false,
  );

  SharedPreferences? _prefs;
  final MytripsServices _supabaseService = MytripsServices();

  // PDF-related state and controllers
  Map<String, PdfState> pdfStates = {};
  final TextEditingController _priceeController = TextEditingController();
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _companyAddressController =
  TextEditingController();
  final TextEditingController _cMobileNumberController =
  TextEditingController();
  final TextEditingController _billtoNameController = TextEditingController();
  final TextEditingController _billtoAddressController =
  TextEditingController();
  final TextEditingController _billtoMobileNumberController =
  TextEditingController();
  final TextEditingController _invoiceNumberController =
  TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _accountNumberController =
  TextEditingController();
  final TextEditingController _ifscController = TextEditingController();
  final TextEditingController _branchController = TextEditingController();
  final TextEditingController _accountHolderController =
  TextEditingController();
  final TextEditingController _gstController = TextEditingController();

  final TextEditingController _taxPercentageController =
  TextEditingController();
  double _calculatedTax = 0.0;
  double _calculatedTotal = 0.0;

  TaxType _selectedTaxType = TaxType.withinState;

  BillingAddress? _fetchedBillingAddress;
  CompanyAddress? _selectedCompanyAddress;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      _prefs = prefs;
      loadCachedShipments();
    });
    _loadUser();
    fetchShipments();
    fetchEditCounts();
    for (var shipment in shipments) {
      final shipmentId = shipment['shipment_id'].toString();
      pdfStates[shipmentId] =
      shipment['Invoice_link'] != null &&
          shipment['Invoice_link'].toString().trim().isNotEmpty
          ? PdfState.uploaded
          : PdfState.notGenerated;
    }
  }

  Future<void> _loadUser() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    final userProfile = await Supabase.instance.client
        .from('user_profiles')
        .select('custom_user_id, role')
        .eq('user_id', currentUserId)
        .maybeSingle();

    setState(() {
      customUserId = userProfile?['custom_user_id'];
      role = userProfile?['role'];
    });
    print("Logged in as: customUserId=$customUserId, role=$role");
  }

  Future<Map<String, String?>> fetchCustomerNameAndMobile(
      String shipperId,
      ) async {
    final response = await Supabase.instance.client
        .from('user_profiles')
        .select('name, mobile_number')
        .eq('custom_user_id', shipperId)
        .maybeSingle();

    if (response != null) {
      return {
        'name': response['name'] as String?,
        'mobile_number': response['mobile_number'] as String?,
      };
    } else {
      return {'name': null, 'mobile_number': null};
    }
  }

  Future<void> fetchEditCounts() async {
    final response = await Supabase.instance.client
        .from('ratings')
        .select(
      'shipment_id, edit_count',
    ); // Corrected 'shipmentId' to 'shipment_id'
    if (response.isNotEmpty) {
      setState(() {
        for (var row in response) {
          ratingEditCount[row['shipment_id']] =
          row['edit_count']; // Corrected 'shipmentId' to 'shipment_id'
        }
      });
    }
  }

  Future<void> loadCachedShipments() async {
    final cachedData = _prefs?.getString('shipments_cache');
    if (cachedData != null) {
      setState(() {
        shipments = List<Map<String, dynamic>>.from(jsonDecode(cachedData));
        filteredShipments = shipments;
        loading = false;
      });
    }
  }

  Future<void> saveShipmentToCache(List<Map<String, dynamic>> shipments) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(shipments);
    await prefs.setString('shipments_cache', jsonStr);
  }

  Future<void> fetchShipments() async {
    setState(() => loading = true);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    print('My current UID: $userId');

    if (userId == null) {
      setState(() {
        loading = false;
        shipments = [];
        filteredShipments = [];
      });
      return;
    }

    // Fetch custom user ID
    final res = await _supabaseService.getShipmentsForUser(userId);
    print('Raw shipments response: $res');

    setState(() {
      loading = false;
      shipments = [];
      filteredShipments = [];
    });

    shipments = res.where((s) {
      final status = s['booking_status']?.toString().toLowerCase();
      print(status);
      return status == 'completed';
    }).toList();

    print("Fetched shipments count: ${res.length}");
    for (var s in res) {
      print(
        "Shipment ID: ${s['shipment_id']}, booking_status: '${s['booking_status']}'",
      );
    }

    print("Filtered completed shipments count: ${shipments.length}");
    for (var s in shipments) {
      print(
        "Completed shipment ID: ${s['shipment_id']}, booking_status: '${s['booking_status']}'",
      );
    }

    filteredShipments = shipments;
    await _prefs?.setString('shipments_cache', jsonEncode(shipments));
    await fetchEditCounts();
    await checkPdfStates();

    setState(() {
      loading = false;
      _refreshController.refreshCompleted();
    });
  }

  void searchShipments(String query) {
    setState(() {
      searchQuery = query;
      applyFilters();
    });
  }

  void filterByStatus(String status) {
    setState(() {
      statusFilter = status;
      applyFilters();
    });
  }

  void applyFilters() {
    filteredShipments = shipments.where((s) {
      final id = s['shipment_id']?.toString().toLowerCase() ?? '';
      final pickup = s['pickup']?.toString().toLowerCase() ?? '';
      final drop = s['drop']?.toString().toLowerCase() ?? '';
      final q = searchQuery.toLowerCase();

      final matchQuery =
          searchQuery.isEmpty ||
              id.contains(q) ||
              pickup.contains(q) ||
              drop.contains(q);

      final matchStatus =
          statusFilter == 'All' ||
              s['booking_status'].toString().toLowerCase() ==
                  statusFilter.toLowerCase();

      return matchQuery && matchStatus;
    }).toList();

    filteredShipments.sort((a, b) {
      final aDate =
          DateTime.tryParse(a['delivery_date'] ?? '') ?? DateTime.now();
      final bDate =
          DateTime.tryParse(b['delivery_date'] ?? '') ?? DateTime.now();
      return bDate.compareTo(aDate);
    });
  }

  // Function for grouping shipments by month
  Map<String, List<Map<String, dynamic>>> groupShipmentsByMonth(
      List<Map<String, dynamic>> shipments,
      ) {
    Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var shipment in shipments) {
      final dateStr = shipment['delivery_date'];
      if (dateStr == null || dateStr.isEmpty) continue;
      try {
        final date = DateTime.parse(dateStr);
        final monthKey = DateFormat.yMMMM().format(date);
        grouped.putIfAbsent(monthKey, () => []);
        grouped[monthKey]!.add(shipment);
      } catch (e) {}
    }

    final now = DateTime.now();
    for (int i = 0; i < 6; i++) {
      final monthDate = DateTime(now.year, now.month - i);
      final monthKey = DateFormat.yMMMM().format(monthDate);
      grouped.putIfAbsent(monthKey, () => []);
    }

    return grouped;
  }

  String getMonthLabel(String monthKey) {
    final now = DateTime.now();
    final currentMonth = DateFormat.yMMMM().format(
      DateTime(now.year, now.month),
    );
    final prevMonth = DateFormat.yMMMM().format(
      DateTime(now.year, now.month - 1),
    );

    if (monthKey == currentMonth) return "This Month";
    if (monthKey == prevMonth) return "Previous Month";
    return monthKey;
  }

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
              leading: CircleAvatar(backgroundColor: Colors.grey, radius: 20),
              title: Container(
                width: double.infinity,
                height: 16,
                color: Colors.grey,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Container(width: 100, height: 12, color: Colors.grey),
                  const SizedBox(height: 4),
                  Container(width: 150, height: 12, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'no_shipments_found'.tr(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'try_refreshing_filters'.tr(),
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: fetchShipments,
            icon: const Icon(Icons.refresh),
            label: Text('refresh'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> fetchBankAndGst() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final response = await Supabase.instance.client
        .from('user_profiles')
        .select('bank_details, gst_number')
        .eq('user_id', user.id)
        .maybeSingle();

    if (response != null) {
      _gstController.text = response['gst_number'] ?? '';

      final bankJson = response['bank_details'];
      if (bankJson != null && bankJson.isNotEmpty) {
        List banks = [];
        if (bankJson is String) {
          banks = jsonDecode(bankJson);
        } else if (bankJson is List) {
          banks = bankJson;
        }

        Map primaryBank = banks.firstWhere(
              (b) => b['is_primary'] == true,
          orElse: () => banks.first,
        );

        _bankNameController.text = primaryBank['bank_name'] ?? '';
        _accountNumberController.text = primaryBank['account_number'] ?? '';
        _ifscController.text = primaryBank['ifsc_code'] ?? '';
        _branchController.text = primaryBank['branch'] ?? '';
        _accountHolderController.text =
            primaryBank['account_holder_name'] ?? '';
      }
    }
  }

  // --------- INTEGRATED INVOICE FUNCTIONS START ----------
  Future fetchBillingAddressForShipment(Map shipment) async {
    final shipperId = shipment['shipper_id'];
    if (shipperId == null) return null;
    final response = await Supabase.instance.client
        .from('user_profiles')
        .select('billing_address')
        .eq('custom_user_id', shipperId)
        .maybeSingle();
    if (response != null &&
        response['billing_address'] != null &&
        response['billing_address'] != '') {
      final map = jsonDecode(response['billing_address']);
      return BillingAddress.fromJson(map);
    }
    return null;
  }

  Future<List<CompanyAddress>> fetchCompanyAddresses() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];
    final response = await Supabase.instance.client
        .from('user_profiles')
        .select('company_address1, company_address2, company_address3')
        .eq('user_id', user.id)
        .maybeSingle();
    final addresses = <CompanyAddress>[];
    if (response != null) {
      for (var key in [
        'company_address1',
        'company_address2',
        'company_address3',
      ]) {
        if (response[key] != null && response[key] != '') {
          final addrMap = jsonDecode(response[key]);
          addresses.add(CompanyAddress.fromJson(addrMap));
        }
      }
    }
    return addresses;
  }

  Future<CompanyAddress?> showCompanyAddressDialog(
      BuildContext context,
      List<CompanyAddress> addresses,
      ) async {
    return await showGeneralDialog<CompanyAddress>(
      context: context,
      barrierDismissible: false, // mandatory, can't close by tapping outside
      barrierLabel: 'company_address'.tr(),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return const SizedBox.shrink(); // required placeholder
      },
      transitionBuilder: (ctx, anim, _, child) {
        final curvedValue =
            Curves.easeInOut.transform(anim.value) - 1.0; // bounce effect

        return Transform(
          transform: Matrix4.translationValues(0.0, curvedValue * -50, 0.0),
          child: Opacity(
            opacity: anim.value,
            child: Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.1),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_city,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'select_company_address'.tr(),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),

                    // Address list
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: addresses.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, index) {
                          final addr = addresses[index];
                          return ListTile(
                            leading: const Icon(Icons.home_outlined),
                            title: Text(
                              "${addr.flatNo}, ${addr.streetName}",
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              "${addr.cityName}, ${addr.district}, ${addr.zipCode}",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                            ),
                            onTap: () => Navigator.pop(ctx, addr),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future checkPdfStates() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final profile = await Supabase.instance.client
        .from('user_profiles')
        .select('custom_user_id,name')
        .eq('user_id', userId)
        .maybeSingle();
    final shipperId = profile?['custom_user_id'];
    for (var shipment in shipments) {
      final shipmentId = shipment['shipment_id'].toString();
      final appDir = await getApplicationDocumentsDirectory();
      final filePath = '${appDir.path}/$shipmentId.pdf';
      if (await File(filePath).exists()) {
        pdfStates[shipmentId] = PdfState.downloaded;
      } else {
        final url = Supabase.instance.client.storage
            .from('invoices')
            .getPublicUrl('$shipperId/$shipmentId.pdf');
        final response = await http.head(Uri.parse(url));
        pdfStates[shipmentId] = response.statusCode == 200
            ? PdfState.uploaded
            : PdfState.notGenerated;
      }
    }
    setState(() {});
  }

  Future generateInvoice(Map<String, dynamic> shipment) async {
    _fetchedBillingAddress = await fetchBillingAddressForShipment(shipment);
    if (_fetchedBillingAddress == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('billing_address_not_found'.tr())));
      return;
    }

    final companyAddresses = await fetchCompanyAddresses();
    if (companyAddresses.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('no_company_addresses'.tr())));
      return;
    }
    if (companyAddresses.length == 1) {
      _selectedCompanyAddress = companyAddresses.first;
    } else {
      _selectedCompanyAddress = await showCompanyAddressDialog(
        context,
        companyAddresses,
      );
      if (_selectedCompanyAddress == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('please_select_company_address'.tr())),
        );
        return;
      }
    }

    final invoiceUrl = await generateInvoicePDF(
      shipment: shipment,
      price: _priceeController.text,
      companyName: _companyNameController.text,
      companyAddress: _selectedCompanyAddress != null
          ? '${_selectedCompanyAddress!.flatNo}, ${_selectedCompanyAddress!.streetName}, ${_selectedCompanyAddress!.cityName}, ${_selectedCompanyAddress!.district}, ${_selectedCompanyAddress!.zipCode}'
          : '',
      companyMobile: _cMobileNumberController.text,
      customerName: _billtoNameController.text,
      customerAddress: '',
      billingAddress: _fetchedBillingAddress,
      customerMobile: _billtoMobileNumberController.text,
      invoiceNo: _invoiceNumberController.text,
      companySelectedAddress: _selectedCompanyAddress,
      bankName: _bankNameController.text,
      accountNumber: _accountNumberController.text,
      ifscCode: _ifscController.text,
      branch: _branchController.text,
      accountHolder: _accountHolderController.text,
      gstNumber: _gstController.text,
      taxPercentage: _taxPercentageController.text,
      taxAmount: _calculatedTax.toString(),
      totalAmount: _calculatedTotal.toString(),
      taxType: _selectedTaxType == TaxType.withinState ? "CGST+SGST" : "IGST",
    );

    // Save URL to shipment
    shipment['Invoice_link'] = invoiceUrl;
    shipment['hasInvoice'] = true;

    pdfStates[shipment['shipment_id'].toString()] = PdfState.uploaded;
    setState(() {});

    // Optionally: update backend with the link
    final shipmentId = shipment['shipment_id'].toString();
    await Supabase.instance.client
        .from('shipment')
        .update({'Invoice_link': invoiceUrl})
        .eq('shipment_id', shipmentId);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('invoice_generated'.tr())));
  }

  //new download function
  Future downloadInvoice(Map shipment) async {
    final shipmentId = shipment['shipment_id'].toString();
    final userId = Supabase.instance.client.auth.currentUser!.id;

    // Get user profile
    final profile = await Supabase.instance.client
        .from('user_profiles')
        .select('custom_user_id,name,role')
        .eq('user_id', userId)
        .maybeSingle();
    final shipperId = profile?['custom_user_id'];
    final userRole =
    profile?['role'];

    String? pdfPath;

    if (userRole == 'agent') {
      pdfPath = '$shipperId/$shipmentId.pdf';
    } else if (userRole == 'shipper') {
      pdfPath = shipment['Invoice_link'] as String?;
      if (pdfPath == null || pdfPath.isEmpty) {
        final shipmentRow = await Supabase.instance.client
            .from('shipment')
            .select('Invoice_link')
            .eq('shipment_id', shipmentId)
            .maybeSingle();
        pdfPath = shipmentRow?['Invoice_link'] as String?;
      }
    }

    if (pdfPath != null && pdfPath.isNotEmpty) {
      final publicUrlResponse = Supabase.instance.client.storage
          .from('invoices')
          .getPublicUrl(pdfPath);
      final pdfUrl = Supabase.instance.client.storage
          .from('invoices')
          .getPublicUrl(pdfPath);
      if (pdfUrl == null || pdfUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('could_not_generate_pdf_url'.tr())),
        );
        return;
      }

      final response = await http.get(Uri.parse(pdfUrl));
      if (response.statusCode == 200) {
        final appDir = await getApplicationDocumentsDirectory();
        final localPath = '${appDir.path}/$shipmentId.pdf';
        final file = File(localPath);
        await file.writeAsBytes(response.bodyBytes, flush: true);

        pdfStates[shipmentId] = PdfState.downloaded;
        setState(() {});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('pdf_downloaded'.tr())));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('pdf_could_not_be_downloaded'.tr())),
        );
      }
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('pdf_link_not_found'.tr())));
    }
  }

  void previewInvoice(BuildContext context, String shipmentId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final localPath = '${appDir.path}/$shipmentId.pdf';
    final file = File(localPath);
    if (await file.exists()) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfPreviewScreen(localPath: localPath),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('pdf_not_found'.tr())));
    }
  }

  Future<void> confirmAndDelete(BuildContext context, Map<String, dynamic> shipment) async {
    final shipmentId = shipment['shipment_id'].toString();
    // Show confirmation dialog
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Invoice?'),
        content: Text('Are you sure you want to delete this invoice?'),
        actions: [
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ElevatedButton(
            child: Text('Delete'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (result != true) return;

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');
      final profile = await Supabase.instance.client
          .from('user_profiles')
          .select('custom_user_id')
          .eq('user_id', userId)
          .maybeSingle();
      final shipperId = profile?['custom_user_id'];
      if (shipperId == null) throw Exception('Shipper ID not found');
      final bucketFilePath = '$shipperId/$shipmentId.pdf';
      await Supabase.instance.client.storage
          .from('invoices')
          .remove([bucketFilePath]);
      final appDir = await getApplicationDocumentsDirectory();
      final localPath = '${appDir.path}/$shipmentId.pdf';
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
      }
      await Supabase.instance.client
          .from('shipment')
          .update({'Invoice_link': null})
          .eq('shipment_id', shipmentId);
      shipment['Invoice_link'] = null;
      shipment['hasInvoice'] = false;
      if (mounted) {
        setState(() {
          pdfStates[shipmentId] = PdfState.notGenerated;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invoice deleted')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting invoice: $e')),
      );
    }
  }

  Future deleteLocalInvoice(String shipmentId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final localPath = '${appDir.path}/$shipmentId.pdf';
    final file = File(localPath);
    if (await file.exists()) {
      await file.delete();
      pdfStates[shipmentId] = PdfState.notGenerated;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('pdf_deleted'.tr())));
    }
  }

  void requestInvoice(Map<String, dynamic> shipment) async {
    final companyId = shipment['assigned_company'];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Requested invoice for Shipment ${shipment['shipment_id']}',
        ),
      ),
    );

    try {
      final response =
      await Supabase.instance.client.from('invoice_requests').insert({
        'shipment_id': shipment['shipment_id'],
        'requested_by': customUserId,
        'requested_to': companyId,
      }).select();

      print("Invoice request logged in Supabase ✅: $response");
    } catch (e) {
      print("Exception while requesting invoice: $e");
    }
  }

  Future shareInvoice(Map shipment) async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final profile = await Supabase.instance.client
        .from('user_profiles')
        .select('custom_user_id')
        .eq('user_id', userId)
        .maybeSingle();
    final shipperId = profile?['custom_user_id'];
    final shipmentId = shipment['shipment_id'].toString();
    final pdfPath = '$shipperId/$shipmentId.pdf';
    try {
      final response = await Supabase.instance.client
          .from('shipment')
          .update({'Invoice_link': pdfPath})
          .eq('shipment_id', shipmentId);
      print('Response update shipment: $response');
      if (response is Map &&
          response.containsKey('error') &&
          response['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share invoice: ${response['error']}'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('invoice_shared_successfully'.tr())),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error sharing invoice: $e')));
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    TextInputType? keyboard,
    void Function(String)? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null ? Icon(icon) : null,
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: Colors.blueAccent,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
  // --------- INTEGRATED INVOICE FUNCTIONS END ----------

  @override
  Widget build(BuildContext context) {
    final groupedShipments = groupShipmentsByMonth(filteredShipments);
    final months = groupedShipments.keys.toList()
      ..sort((a, b) {
        final da = DateFormat.yMMMM().parse(a);
        final db = DateFormat.yMMMM().parse(b);
        return db.compareTo(da);
      });

    if (selectedMonth == null && months.isNotEmpty) {
      selectedMonth = months.first;
    }

    return StatefulBuilder(
      builder: (context, setState) {
        final shipmentsToShow = groupedShipments[selectedMonth]!;
        return Scaffold(
          appBar: AppBar(
            title: Text('shipment_history'.tr()),
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () async {
                  final result = await showSearch(
                    context: context,
                    delegate: ShipmentSearchDelegate(shipments: shipments),
                  );
                  if (result != null) searchShipments(result);
                },
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: fetchShipments,
            child: loading
                ? buildSkeletonLoader()
                : filteredShipments.isEmpty
                ? buildEmptyState()
                : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: "select_month".tr(),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedMonth,
                        isExpanded: true,
                        hint: Text("choose_month".tr()),
                        icon: const Icon(
                          Icons.calendar_month,
                          color: Colors.blue,
                        ),
                        onChanged: (value) {
                          setState(() => selectedMonth = value);
                        },
                        items: months.map((m) {
                          final label = getMonthLabel(m);
                          return DropdownMenuItem(
                            value: m,
                            child: Text(label),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                const Divider(thickness: 1),

                Expanded(
                  child: shipmentsToShow.isEmpty
                      ? Center(
                    child: Text(
                      "No shipments in $selectedMonth",
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  )
                      : ListView.builder(
                    itemCount: shipmentsToShow.length,
                    itemBuilder: (_, i) {
                      final shipment = shipmentsToShow[i];
                      return shipment_card.ShipmentCard(
                        shipment: shipment,
                        pdfStates: pdfStates,
                        onTap: () {
                          print(
                            "Building card for shipment ID: ${shipment['shipment_id']}, pdfState: $pdfStates",
                          );
                        },
                        onPreviewInvoice: () {
                          previewInvoice(
                            context,
                            shipment['shipment_id'].toString(),
                          );
                        },
                        onDownloadInvoice: () async {
                          await downloadInvoice(shipment);
                          setState(() {
                            pdfStates[shipment['shipment_id']
                                .toString()] =
                                PdfState.downloaded;
                          });
                        },

                        onRequestInvoice: () {
                          requestInvoice(shipment);
                        },
                        onGenerateInvoice: () async {
                          await fetchBankAndGst(); // fetch bank + gst before showing dialog
                          final shipperId = shipment['shipper_id']
                              ?.toString();
                          if (shipperId != null) {
                            final customerInfo =
                            await fetchCustomerNameAndMobile(
                              shipperId,
                            );

                            // Set controllers before showing the dialog
                            _billtoNameController.text =
                                customerInfo['name'] ?? '';
                            _billtoMobileNumberController.text =
                                customerInfo['mobile_number'] ?? '';
                          }
                          await showDialog(
                            context: context,
                            builder: (_) => StatefulBuilder(
                              builder: (context, setState) {
                                void _recalculateTotals() {
                                  final price =
                                      double.tryParse(
                                        _priceeController.text,
                                      ) ??
                                          0.0;
                                  final taxPercent =
                                      double.tryParse(
                                        _taxPercentageController
                                            .text,
                                      ) ??
                                          0.0;

                                  if (taxPercent <= 0 ||
                                      price <= 0) {
                                    setState(() {
                                      _calculatedTax = 0.0;
                                      _calculatedTotal = price;
                                    });
                                    return;
                                  }

                                  _calculatedTax =
                                      (price * taxPercent) / 100;
                                  _calculatedTotal =
                                      price + _calculatedTax;

                                  setState(() {});
                                }

                                return Dialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(20),
                                  ),
                                  child: ConstrainedBox(
                                    constraints:
                                    const BoxConstraints(
                                      maxWidth: 450,
                                      maxHeight: 600,
                                    ),
                                    child: Column(
                                      mainAxisSize:
                                      MainAxisSize.min,
                                      children: [
                                        // Title Bar
                                        Container(
                                          width: double.infinity,
                                          padding:
                                          const EdgeInsets.all(
                                            16,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withOpacity(0.1),
                                            borderRadius:
                                            const BorderRadius.vertical(
                                              top:
                                              Radius.circular(
                                                20,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.receipt_long,
                                                color:
                                                Theme.of(
                                                  context,
                                                )
                                                    .colorScheme
                                                    .primary,
                                              ),
                                              const SizedBox(
                                                width: 8,
                                              ),
                                              Text(
                                                "invoice_details"
                                                    .tr(),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge
                                                    ?.copyWith(
                                                  fontWeight:
                                                  FontWeight
                                                      .bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Form content
                                        Expanded(
                                          child: SingleChildScrollView(
                                            padding:
                                            const EdgeInsets.all(
                                              16,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .start,
                                              children: [
                                                // Company Info
                                                Text(
                                                  "company_information"
                                                      .tr(),
                                                  style: TextStyle(
                                                    fontWeight:
                                                    FontWeight
                                                        .bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const Divider(),
                                                const SizedBox(
                                                  height: 8,
                                                ),
                                                _buildTextField(
                                                  controller:
                                                  _companyNameController,
                                                  label:
                                                  "company_name"
                                                      .tr(),
                                                  icon: Icons
                                                      .business,
                                                ),
                                                _buildTextField(
                                                  controller:
                                                  _cMobileNumberController,
                                                  label:
                                                  "company_mobile_no"
                                                      .tr(),
                                                  keyboard:
                                                  TextInputType
                                                      .phone,
                                                  icon: Icons.phone,
                                                ),
                                                _buildTextField(
                                                  controller:
                                                  _gstController,
                                                  label:
                                                  "gst_number"
                                                      .tr(),
                                                  icon: Icons
                                                      .assignment_outlined,
                                                ),

                                                const SizedBox(
                                                  height: 16,
                                                ),

                                                // --- Bank Info ---
                                                Text(
                                                  "bank_details"
                                                      .tr(),
                                                  style: TextStyle(
                                                    fontWeight:
                                                    FontWeight
                                                        .bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const Divider(),
                                                _buildTextField(
                                                  controller:
                                                  _bankNameController,
                                                  label: "bank_name"
                                                      .tr(),
                                                  icon: Icons
                                                      .account_balance,
                                                ),
                                                _buildTextField(
                                                  controller:
                                                  _accountNumberController,
                                                  label:
                                                  "account_number"
                                                      .tr(),
                                                  keyboard:
                                                  TextInputType
                                                      .number,
                                                  icon: Icons
                                                      .credit_card,
                                                ),
                                                _buildTextField(
                                                  controller:
                                                  _ifscController,
                                                  label: "ifsc_code"
                                                      .tr(),
                                                  icon: Icons
                                                      .qr_code_2,
                                                ),
                                                _buildTextField(
                                                  controller:
                                                  _branchController,
                                                  label: "branch"
                                                      .tr(),
                                                  icon: Icons
                                                      .location_city_outlined,
                                                ),
                                                _buildTextField(
                                                  controller:
                                                  _accountHolderController,
                                                  label:
                                                  "account_holder_name"
                                                      .tr(),
                                                  icon:
                                                  Icons.person,
                                                ),

                                                const SizedBox(
                                                  height: 16,
                                                ),

                                                // --- Customer Info ---
                                                Text(
                                                  "customer_information"
                                                      .tr(),
                                                  style: TextStyle(
                                                    fontWeight:
                                                    FontWeight
                                                        .bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const Divider(),
                                                _buildTextField(
                                                  controller:
                                                  _billtoNameController,
                                                  label:
                                                  "customer_name"
                                                      .tr(),
                                                  icon: Icons
                                                      .person_outline,
                                                ),
                                                _buildTextField(
                                                  controller:
                                                  _billtoMobileNumberController,
                                                  label:
                                                  "customer_mobile_no"
                                                      .tr(),
                                                  keyboard:
                                                  TextInputType
                                                      .phone,
                                                  icon: Icons
                                                      .phone_android,
                                                ),

                                                const SizedBox(
                                                  height: 16,
                                                ),

                                                // --- Invoice ---
                                                _buildTextField(
                                                  controller:
                                                  _invoiceNumberController,
                                                  label:
                                                  "invoice_no"
                                                      .tr(),
                                                  icon:
                                                  Icons.receipt,
                                                ),
                                                _buildTextField(
                                                  controller:
                                                  _priceeController,
                                                  label: "price"
                                                      .tr(),
                                                  keyboard:
                                                  const TextInputType.numberWithOptions(
                                                    decimal:
                                                    true,
                                                  ),
                                                  icon: Icons
                                                      .currency_rupee,
                                                  onChanged: (_) =>
                                                      _recalculateTotals(),
                                                ),

                                                const SizedBox(
                                                  height: 16,
                                                ),

                                                // --- Tax Details ---
                                                Text(
                                                  "tax_details"
                                                      .tr(),
                                                  style: TextStyle(
                                                    fontWeight:
                                                    FontWeight
                                                        .bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const Divider(),
                                                _buildTextField(
                                                  controller:
                                                  _taxPercentageController,
                                                  label:
                                                  "tax_percentage"
                                                      .tr(),
                                                  keyboard:
                                                  const TextInputType.numberWithOptions(
                                                    decimal:
                                                    true,
                                                  ),
                                                  icon:
                                                  Icons.percent,
                                                  onChanged: (_) =>
                                                      _recalculateTotals(),
                                                ),

                                                RadioListTile<
                                                    TaxType
                                                >(
                                                  title: Text(
                                                    "within_state"
                                                        .tr(),
                                                  ),
                                                  value: TaxType
                                                      .withinState,
                                                  groupValue:
                                                  _selectedTaxType,
                                                  onChanged: (val) {
                                                    setState(() {
                                                      _selectedTaxType =
                                                      val!;
                                                      _recalculateTotals();
                                                    });
                                                  },
                                                ),
                                                RadioListTile<
                                                    TaxType
                                                >(
                                                  title: Text(
                                                    "outside_state"
                                                        .tr(),
                                                  ),
                                                  value: TaxType
                                                      .outsideState,
                                                  groupValue:
                                                  _selectedTaxType,
                                                  onChanged: (val) {
                                                    setState(() {
                                                      _selectedTaxType =
                                                      val!;
                                                      _recalculateTotals();
                                                    });
                                                  },
                                                ),

                                                const SizedBox(
                                                  height: 8,
                                                ),
                                                Text(
                                                  "Tax Amount: ₹${_calculatedTax.toStringAsFixed(2)}",
                                                  style: const TextStyle(
                                                    fontWeight:
                                                    FontWeight
                                                        .w600,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                Text(
                                                  "Total: ₹${_calculatedTotal.toStringAsFixed(2)}",
                                                  style: const TextStyle(
                                                    fontWeight:
                                                    FontWeight
                                                        .w600,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                        // --- Buttons ---
                                        Padding(
                                          padding:
                                          const EdgeInsets.all(
                                            12,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                      ),
                                                  style: OutlinedButton.styleFrom(
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                      BorderRadius.circular(
                                                        12,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    "cancel".tr(),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(
                                                width: 12,
                                              ),
                                              Expanded(
                                                child: ElevatedButton(
                                                  onPressed: () async {
                                                    if (_companyNameController
                                                        .text
                                                        .isEmpty ||
                                                        _cMobileNumberController
                                                            .text
                                                            .isEmpty ||
                                                        _gstController
                                                            .text
                                                            .isEmpty ||
                                                        _bankNameController
                                                            .text
                                                            .isEmpty ||
                                                        _accountNumberController
                                                            .text
                                                            .isEmpty ||
                                                        _ifscController
                                                            .text
                                                            .isEmpty ||
                                                        _branchController
                                                            .text
                                                            .isEmpty ||
                                                        _accountHolderController
                                                            .text
                                                            .isEmpty ||
                                                        _billtoNameController
                                                            .text
                                                            .isEmpty ||
                                                        _billtoMobileNumberController
                                                            .text
                                                            .isEmpty ||
                                                        _invoiceNumberController
                                                            .text
                                                            .isEmpty ||
                                                        _priceeController
                                                            .text
                                                            .isEmpty ||
                                                        _taxPercentageController
                                                            .text
                                                            .isEmpty) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'please_fill_required'
                                                                .tr(),
                                                          ),
                                                        ),
                                                      );
                                                      return;
                                                    }

                                                    Navigator.pop(
                                                      context,
                                                    );
                                                    await generateInvoice(
                                                      shipment,
                                                    );
                                                    setState(() {
                                                      pdfStates[shipment['shipment_id']
                                                          .toString()] =
                                                          PdfState
                                                              .uploaded;
                                                    });

                                                    // Clear fields
                                                    _companyNameController
                                                        .clear();
                                                    _cMobileNumberController
                                                        .clear();
                                                    _gstController
                                                        .clear();
                                                    _bankNameController
                                                        .clear();
                                                    _accountNumberController
                                                        .clear();
                                                    _ifscController
                                                        .clear();
                                                    _branchController
                                                        .clear();
                                                    _accountHolderController
                                                        .clear();
                                                    _billtoNameController
                                                        .clear();
                                                    _billtoMobileNumberController
                                                        .clear();
                                                    _invoiceNumberController
                                                        .clear();
                                                    _priceeController
                                                        .clear();
                                                    _taxPercentageController
                                                        .clear();
                                                    _calculatedTax =
                                                    0.0;
                                                    _calculatedTotal =
                                                    0.0;
                                                  },
                                                  style: ElevatedButton.styleFrom(
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                      BorderRadius.circular(
                                                        12,
                                                      ),
                                                    ),
                                                    minimumSize:
                                                    const Size.fromHeight(
                                                      45,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    "generate".tr(),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },

                        onDeleteInvoice: () async {
                          await confirmAndDelete(context, shipment);

                          // Update state to "notGenerated"
                          setState(() {
                            pdfStates[shipment['shipment_id']
                                .toString()] =
                                PdfState.notGenerated;
                          });
                        },

                        onShareInvoice: () async {
                          await shareInvoice(shipment);
                        },
                        customUserId: customUserId,
                        role: role,
                        // pdfStates: pdfStates,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ShipmentSearchDelegate
class ShipmentSearchDelegate extends SearchDelegate<String> {
  final List<Map<String, dynamic>> shipments;
  ShipmentSearchDelegate({required this.shipments});

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, ''),
  );

  @override
  Widget buildResults(BuildContext context) => Container();

  @override
  Widget buildSuggestions(BuildContext context) {
    final q = query.toLowerCase();
    if (q.isEmpty) {
      return Center(
        child: Text(
          "type_shipment_search".tr(),
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    final results = shipments.where((s) {
      final id = s['shipment_id']?.toString().toLowerCase() ?? '';
      final pickup = s['pickup']?.toString().toLowerCase() ?? '';
      final drop = s['drop']?.toString().toLowerCase() ?? '';
      return id.contains(q) || pickup.contains(q) || drop.contains(q);
    }).toList();

    if (results.isEmpty) {
      return Center(child: Text("No matching shipments for '$query'"));
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final s = results[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: const Icon(Icons.local_shipping, color: Colors.blue),
            title: Text(
              "Shipment ID: ${s['shipment_id']}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${s['pickup']} -> ${s['drop']}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (s['delivery_date'] != null)
                  Text(
                    "Completed At: ${s['delivery_date']}",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
            onTap: () {},
          ),
        );
      },
    );
  }
}

// PDF Preview Screen
class PdfPreviewScreen extends StatelessWidget {
  final String localPath;
  const PdfPreviewScreen({required this.localPath, Key? key}) : super(key: key);
  void sharePdf() {
    Share.shareXFiles([XFile(localPath)], text: 'sharing_invoice_pdf'.tr());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('invoice_preview'.tr()),
        actions: [
          IconButton(
            onPressed: sharePdf,
            icon: Icon(Icons.share),
            tooltip: 'share_pdf'.tr(),
          ),
        ],
      ),
      body: SafeArea(child: PDFView(filePath: localPath)),
    );
  }
}