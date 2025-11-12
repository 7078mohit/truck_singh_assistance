import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:logistics_toolkit/config/theme.dart';
import '../../services/user_data_service.dart';

enum UserRole { agent, truckOwner, driver }

class DriverDocumentsPage extends StatefulWidget {
  const DriverDocumentsPage({super.key});

  @override
  State<DriverDocumentsPage> createState() => _DriverDocumentsPageState();
}

class _DriverDocumentsPageState extends State<DriverDocumentsPage>
    with TickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _uploadingDriverId;
  String? _uploadingDocType;
  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _filteredDrivers = [];
  String? _loggedInUserId;
  UserRole? _userRole;
  late AnimationController _animationController;
  String _selectedStatusFilter = 'All';
  final List<String> _statusFilters = [
    'All',
    'Pending',
    'Approved',
    'Rejected',
  ];

  final Map<String, Map<String, dynamic>> _personalDocuments = {
    'Drivers License': {
      'icon': Icons.credit_card,
      'description': 'Valid driving license',
      'color': Colors.blue,
    },
    'Aadhaar Card': {
      'icon': Icons.badge,
      'description': 'Government identity card',
      'color': Colors.green,
    },
    'PAN Card': {
      'icon': Icons.credit_card_outlined,
      'description': 'PAN card for tax identification',
      'color': Colors.orange,
    },
    'Profile Photo': {
      'icon': Icons.person,
      'description': 'Driver profile photograph',
      'color': Colors.purple,
    },
  };

  @override
  void initState() {
    super.initState();
    _animationController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _initializeData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    await _detectUserRole();
    await _loadDriverDocuments();
  }

  Future<void> _detectUserRole() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final profile = await supabase
          .from('user_profiles')
          .select('custom_user_id, role')
          .eq('user_id', userId)
          .single();

      _loggedInUserId = profile['custom_user_id'];
      final userType = profile['role'];

      if (userType == 'agent') {
        _userRole = UserRole.agent;
      } else if (_loggedInUserId!.startsWith('TRUK')) {
        _userRole = UserRole.truckOwner;
      } else if (_loggedInUserId!.startsWith('DRV')) {
        _userRole = UserRole.driver;
      }
    } catch (_) {
      if (_loggedInUserId?.startsWith('TRUK') == true) {
        _userRole = UserRole.truckOwner;
      } else {
        _userRole = UserRole.driver;
      }
    }
  }

  Future<void> _loadDriverDocuments() async {
    setState(() => _isLoading = true);
    try {
      List<Map<String, dynamic>> relations = [];

      if (_userRole == UserRole.agent || _userRole == UserRole.truckOwner) {
        relations = await supabase
            .from('driver_relation')
            .select('driver_custom_id')
            .eq('owner_custom_id', _loggedInUserId!);
      } else if (_userRole == UserRole.driver) {
        relations = [
          {'driver_custom_id': _loggedInUserId},
        ];
      }

      if (relations.isEmpty) {
        setState(() {
          _drivers = [];
          _filteredDrivers = [];
          _isLoading = false;
        });
        return;
      }

      final driverIds = relations
          .map((r) => r['driver_custom_id'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toList();

      final driverProfiles = await supabase
          .from('user_profiles')
          .select('custom_user_id, name, email, mobile_number')
          .inFilter('custom_user_id', driverIds);

      final uploadedDocs = await supabase
          .from('driver_documents')
          .select(
        'driver_custom_id, document_type, updated_at, file_url, status, file_path, rejection_reason, submitted_at, reviewed_at, reviewed_by, uploaded_by_role, owner_custom_id, truck_owner_id, document_category',
      )
          .inFilter('driver_custom_id', driverIds)
          .eq('document_category', 'personal');

      final driversWithStatus = driverProfiles.map((driver) {
        final driverId = driver['custom_user_id'];
        final docs = uploadedDocs
            .where((d) => d['driver_custom_id'] == driverId)
            .toList();

        final docStatus = <String, Map<String, dynamic>>{};
        for (var docType in _personalDocuments.keys) {
          final matched = docs.where((d) => d['document_type'] == docType).toList();
          matched.sort((a, b) {
            final aTime = DateTime.tryParse(a['updated_at'] ?? '') ?? DateTime(1970);
            final bTime = DateTime.tryParse(b['updated_at'] ?? '') ?? DateTime(1970);
            return bTime.compareTo(aTime);
          });
          final doc = matched.isNotEmpty ? matched.first : {};
          docStatus[docType] = {
            'status': doc.isEmpty ? 'Not Uploaded' : (doc['status'] ?? 'pending'),
            'file_url': doc['file_url'],
            'rejection_reason': doc['rejection_reason'],
          };
        }
        return {
          'custom_user_id': driverId,
          'name': driver['name'] ?? 'Unknown',
          'documents': docStatus,
        };
      }).toList();

      setState(() {
        _drivers = driversWithStatus;
        _applyStatusFilter();
        _isLoading = false;
      });
    } catch (e) {
      _showErrorSnackBar(e.toString());
      setState(() => _isLoading = false);
    }
  }

  void _applyStatusFilter() {
    if (_selectedStatusFilter == 'All') {
      _filteredDrivers = List.from(_drivers);
    } else {
      final filter = _selectedStatusFilter.toLowerCase();
      _filteredDrivers = _drivers.where((driver) {
        final docs = driver['documents'] as Map<String, Map<String, dynamic>>;
        return docs.values.any(
              (doc) => (doc['status'] ?? '').toString().toLowerCase() == filter,
        );
      }).toList();
    }
  }

  Future<void> _uploadDocument(String driverId, String docType) async {
    if (_userRole == UserRole.driver && driverId != _loggedInUserId) {
      _showErrorSnackBar('Drivers can only upload their own documents');
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result == null || result.files.isEmpty) return;

      setState(() {
        _uploadingDriverId = driverId;
        _uploadingDocType = docType;
      });

      final file = File(result.files.single.path!);
      final ext = result.files.single.extension ?? 'jpg';
      final fileName =
          '${driverId}_${docType.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final filePath = 'driver_documents/$fileName';

      await supabase.storage.from('driver-documents').upload(filePath, file);
      final url = supabase.storage.from('driver-documents').getPublicUrl(filePath);

      await supabase.from('driver_documents').upsert({
        'driver_custom_id': driverId,
        'document_type': docType,
        'file_url': url,
        'file_path': filePath,
        'status': 'pending',
        'submitted_at': DateTime.now().toIso8601String(),
        'uploaded_by_role': _userRole.toString(),
        'document_category': 'personal',
        'user_id': supabase.auth.currentUser?.id,
      });

      _showSuccessSnackBar('Uploaded successfully');
      await _loadDriverDocuments();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    } finally {
      setState(() {
        _uploadingDriverId = null;
        _uploadingDocType = null;
      });
    }
  }

  Future<void> _approveDocument(String driverId, String docType) async {
    if (_userRole == UserRole.driver) {
      _showErrorSnackBar('drivers_cannot_approve_documents'.tr());
      return;
    }
    try {
      final docs = await supabase
          .from('driver_documents')
          .select('id')
          .eq('driver_custom_id', driverId)
          .eq('document_type', docType);
      if (docs.isEmpty) return;
      final docId = docs.first['id'];
      await supabase.rpc('approve_driver_document', params: {
        'p_document_id': docId,
        'p_reviewed_by': supabase.auth.currentUser?.id,
        'p_reviewed_at': DateTime.now().toIso8601String(),
      });
      _showSuccessSnackBar('Document approved');
      await _loadDriverDocuments();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _rejectDocument(String driverId, String docType) async {
    if (_userRole == UserRole.driver) {
      _showErrorSnackBar('drivers_cannot_reject_documents'.tr());
      return;
    }
    final reason = await _showRejectDialog();
    if (reason == null || reason.isEmpty) return;
    try {
      final docs = await supabase
          .from('driver_documents')
          .select('id')
          .eq('driver_custom_id', driverId)
          .eq('document_type', docType);
      if (docs.isEmpty) return;
      final docId = docs.first['id'];
      await supabase.rpc('reject_driver_document', params: {
        'p_document_id': docId,
        'p_reviewed_by': supabase.auth.currentUser?.id,
        'p_rejection_reason': reason,
        'p_reviewed_at': DateTime.now().toIso8601String(),
      });
      _showSuccessSnackBar('Document rejected');
      await _loadDriverDocuments();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<String?> _showRejectDialog() async {
    String? reason;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('reject_document'.tr()),
        content: TextField(
          onChanged: (v) => reason = v,
          decoration: InputDecoration(
            hintText: 'enter_rejection_reason'.tr(),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('cancel'.tr())),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, reason),
              child: Text('reject'.tr())),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _showSuccessSnackBar(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    final roleText = _userRole == UserRole.agent
        ? 'Agent'
        : _userRole == UserRole.truckOwner
        ? 'Truck Owner'
        : 'Driver';

    return Scaffold(
      appBar: AppBar(
        title: Text('driver_documents'.tr()),
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (_userRole != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text(roleText,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
                backgroundColor: AppColors.teal.withOpacity(0.8),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userRole == UserRole.driver
          ? _buildDriverUploadInterface()
          : _buildAllDriversList(),
    );
  }

  Widget _buildAllDriversList() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Text('filter'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _statusFilters.map((status) {
                    final selected = _selectedStatusFilter == status;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(status),
                        selected: selected,
                        onSelected: (v) {
                          setState(() {
                            _selectedStatusFilter = status;
                            _applyStatusFilter();
                          });
                        },
                        backgroundColor: selected ? AppColors.teal : null,
                        selectedColor: AppColors.teal,
                        labelStyle:
                        TextStyle(color: selected ? Colors.white : Colors.black),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ]),
        ),
        Expanded(
          child: _filteredDrivers.isEmpty
              ? Center(child: Text('no_drivers_found'.tr()))
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _filteredDrivers.length,
            itemBuilder: (c, i) => _buildDriverCard(_filteredDrivers[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildDriverCard(Map<String, dynamic> driver) {
    final driverId = driver['custom_user_id'];
    final driverName = driver['name'];
    final docs = driver['documents'] as Map<String, Map<String, dynamic>>;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.teal,
          child: Text(driverName[0].toUpperCase(),
              style: const TextStyle(color: Colors.white)),
        ),
        title: Text(driverName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(driverId),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: _personalDocuments.entries.map((e) {
                final docType = e.key;
                final docConfig = e.value;
                final docStatus = docs[docType] ?? {};
                return _buildDocumentTile(driverId, docType, docConfig, docStatus);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentTile(String driverId, String docType,
      Map<String, dynamic> docConfig, Map<String, dynamic> docStatus) {
    final status = docStatus['status'] ?? 'Not Uploaded';
    final fileUrl = docStatus['file_url'];
    final rejectionReason = docStatus['rejection_reason'];
    final uploading = _uploadingDriverId == driverId && _uploadingDocType == docType;
    bool canUpload = false;

    if (_userRole == UserRole.agent ||
        _userRole == UserRole.truckOwner ||
        (_userRole == UserRole.driver && driverId == _loggedInUserId)) {
      canUpload = true;
    }

    Color color;
    switch (status.toString().toLowerCase()) {
      case 'approved':
        color = Colors.green;
        break;
      case 'rejected':
        color = Colors.red;
        break;
      case 'pending':
        color = Colors.orange;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(docConfig['icon'], color: docConfig['color']),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(docType, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(docConfig['description'],
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      border: Border.all(color: color),
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(status,
                      style: TextStyle(
                          color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                if (rejectionReason != null && rejectionReason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Reason: $rejectionReason',
                        style: const TextStyle(color: Colors.red, fontSize: 11)),
                  )
              ]),
        ),
        const SizedBox(width: 8),
        if (uploading)
          const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else
          _buildActionButtons(driverId, docType, status, fileUrl, canUpload),
      ]),
    );
  }

  Widget _buildActionButtons(String driverId, String docType, String status,
      String? fileUrl, bool canUpload) {
    final statusLower = status.toString().toLowerCase();
    final buttons = <Widget>[];

    if ((statusLower == 'not uploaded' || statusLower == 'rejected') && canUpload) {
      buttons.add(ElevatedButton(
        onPressed: () => _uploadDocument(driverId, docType),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.teal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        child: Text(statusLower == 'rejected' ? 'Re-upload' : 'Upload',
            style: const TextStyle(fontSize: 10)),
      ));
    }

    if (status != 'Not Uploaded' && fileUrl != null) {
      buttons.add(IconButton(
        icon: Icon(Icons.visibility_outlined, color: AppColors.teal, size: 18),
        onPressed: () async {
          final uri = Uri.parse(fileUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
      ));
    }

    if (statusLower == 'pending' &&
        (_userRole == UserRole.agent || _userRole == UserRole.truckOwner)) {
      buttons.addAll([
        IconButton(
          icon: const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
          onPressed: () => _approveDocument(driverId, docType),
        ),
        IconButton(
          icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
          onPressed: () => _rejectDocument(driverId, docType),
        ),
      ]);
    }

    return Wrap(spacing: 4, children: buttons);
  }

  Widget _buildDriverUploadInterface() {
    final driverDocs = _drivers.isNotEmpty
        ? _drivers.first['documents'] as Map<String, Map<String, dynamic>>
        : <String, Map<String, dynamic>>{};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _personalDocuments.entries.map((entry) {
          final docType = entry.key;
          final docData = driverDocs[docType] ?? {'status': 'Not Uploaded'};
          final status = docData['status'] ?? 'Not Uploaded';
          final rejectionReason = docData['rejection_reason'] as String?;
          final statusLower = status.toString().toLowerCase();

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(entry.value['icon'], color: AppColors.teal, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(docType,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      _buildStatusChip(status),
                    ]),
                    const SizedBox(height: 10),
                    if (rejectionReason != null && rejectionReason.isNotEmpty)
                      Text('Reason: $rejectionReason',
                          style: const TextStyle(color: Colors.red, fontSize: 12)),
                    const SizedBox(height: 10),
                    if (statusLower == 'not uploaded' ||
                        statusLower == 'rejected')
                      ElevatedButton.icon(
                        onPressed: () => _uploadDocument(_loggedInUserId!, docType),
                        icon: const Icon(Icons.upload_file, size: 16),
                        label: Text(statusLower == 'rejected'
                            ? 'Re-upload'
                            : 'Upload'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.teal,
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ]),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color bg, text;
    switch (status.toLowerCase()) {
      case 'approved':
        bg = Colors.green.shade100;
        text = Colors.green.shade800;
        break;
      case 'rejected':
        bg = Colors.red.shade100;
        text = Colors.red.shade800;
        break;
      case 'pending':
        bg = Colors.orange.shade100;
        text = Colors.orange.shade800;
        break;
      default:
        bg = Colors.grey.shade100;
        text = Colors.grey.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
      BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(status,
          style: TextStyle(color: text, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}