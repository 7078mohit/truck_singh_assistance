import 'dart:io';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:logistics_toolkit/config/theme.dart';
import 'package:intl/intl.dart';
import '../../services/user_data_service.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart' as ptr;


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
  final ptr.RefreshController _refreshController =
  ptr.RefreshController(initialRefresh: false);


  // ONLY personal documents that drivers can upload
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
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
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

      print('Detected role for user $_loggedInUserId: $_userRole');
    } catch (e) {
      print('Error detecting user role: $e');
      // Fallback logic
      if (_loggedInUserId?.startsWith('TRUK') == true) {
        _userRole = UserRole.truckOwner;
      } else if (_loggedInUserId?.startsWith('DRV') == true) {
        _userRole = UserRole.driver;
      } else {
        _userRole = UserRole.driver;
      }
    }
  }

  Future<void> _loadDriverDocuments() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      List<Map<String, dynamic>> relations = [];

      // Get drivers based on user role
      if (_userRole == UserRole.agent || _userRole == UserRole.truckOwner) {
        // Agents and truck owners can see their assigned drivers
        relations = await supabase
            .from('driver_relation')
            .select('driver_custom_id')
            .eq('owner_custom_id', _loggedInUserId!);
      } else if (_userRole == UserRole.driver) {
        // Drivers can only see their own documents
        relations = [
          {'driver_custom_id': _loggedInUserId},
        ];
      }

      print('User role: $_userRole, User ID: $_loggedInUserId');
      print('Found relations: ${relations.length} - $relations');

      if (relations.isEmpty) {
        setState(() {
          _drivers = [];
          _filteredDrivers = [];
          _isLoading = false;
        });
        return;
      }

      // Get driver profile information
      final driverIds = relations
          .map((rel) => rel['driver_custom_id'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toList();

      final driverProfiles = await supabase
          .from('user_profiles')
          .select('custom_user_id, name, email, mobile_number')
          .inFilter('custom_user_id', driverIds);

      print('Driver IDs to fetch: $driverIds');
      print(
        'Found driver profiles: ${driverProfiles.length} - $driverProfiles',
      );

      // Get all personal documents for these drivers
      final uploadedDocs = await supabase
          .from('driver_documents')
          .select(
        'driver_custom_id, document_type, updated_at, file_url, status, file_path, rejection_reason, submitted_at, reviewed_at, reviewed_by, uploaded_by_role, owner_custom_id, truck_owner_id, document_category',
      )
          .inFilter('driver_custom_id', driverIds)
          .eq('document_category', 'personal'); // ONLY personal documents

      print('Raw uploaded docs from database: $uploadedDocs');

      final driversWithStatus = driverProfiles
          .map((driver) {
        final driverId = driver['custom_user_id'];
        if (driverId == null || driverId.isEmpty) return null;

        final docsForThisDriver = uploadedDocs
            .where((doc) => doc['driver_custom_id'] == driverId)
            .toList();

        final docStatus = <String, Map<String, dynamic>>{};
        for (var type in _personalDocuments.keys) {
          // Get all documents of this type for this driver
          final docsOfType = docsForThisDriver
              .where((d) => d['document_type'] == type)
              .toList();

          // Sort by updated_at descending to get the most recent record first
          docsOfType.sort((a, b) {
            final aTime =
                DateTime.tryParse(a['updated_at'] ?? '') ?? DateTime(1970);
            final bTime =
                DateTime.tryParse(b['updated_at'] ?? '') ?? DateTime(1970);
            return bTime.compareTo(
              aTime,
            ); // Descending order (most recent first)
          });

          // Take the most recent record, or empty if none found
          final doc = docsOfType.isNotEmpty
              ? docsOfType.first
              : <String, dynamic>{};

          final statusValue = doc.isEmpty
              ? 'Not Uploaded'
              : (doc['status'] ?? 'pending');

          if (doc.isNotEmpty) {
            print(
              'Document status for $driverId-$type: ${doc['status']} -> $statusValue',
            );
          }

          docStatus[type] = {
            'status': statusValue,
            'file_url': doc['file_url'],
            'file_path': doc['file_path'],
            'updated_at': doc['updated_at'],
            'rejection_reason': doc['rejection_reason'],
            'submitted_at': doc['submitted_at'],
            'reviewed_at': doc['reviewed_at'],
            'reviewed_by': doc['reviewed_by'],
          };
        }

        return {
          'custom_user_id': driverId,
          'name': driver['name'] ?? 'Unknown Driver',
          'email': driver['email'] ?? '',
          'mobile_number': driver['mobile_number'] ?? '',
          'documents': docStatus,
        };
      })
          .where((driver) => driver != null)
          .cast<Map<String, dynamic>>()
          .toList();

      setState(() {
        _drivers = driversWithStatus;
        _applyStatusFilter();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading driver documents: $e');
      setState(() {
        _isLoading = false;
      });
      _refreshController.refreshCompleted();
      _showErrorSnackBar('Error loading documents: ${e.toString()}');
    }
  }

  void _applyStatusFilter() {
    if (_selectedStatusFilter == 'All') {
      _filteredDrivers = List.from(_drivers);
    } else {
      _filteredDrivers = _drivers.where((driver) {
        final docs = driver['documents'] as Map<String, Map<String, dynamic>>;
        return docs.values.any((doc) => doc['status'] == _selectedStatusFilter);
      }).toList();
    }
  }

  Future<void> _uploadDocument(String driverId, String docType) async {
    // Check permissions
    if (_userRole == UserRole.driver && driverId != _loggedInUserId) {
      _showErrorSnackBar('Drivers can only upload their own documents');
      return;
    }

    // Agents and truck owners can upload documents for drivers (especially when re-uploading rejected docs)

    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result == null || result.files.isEmpty) return;

      setState(() {
        _uploadingDriverId = driverId;
        _uploadingDocType = docType;
      });

      final file = File(result.files.single.path!);
      final fileExtension = result.files.single.extension ?? 'jpg';
      final fileName =
          '${driverId}_${docType.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final filePath = 'driver_documents/$fileName';

      // Delete existing document if it exists
      try {
        final existingDocs = await supabase
            .from('driver_documents')
            .select('file_path')
            .eq('driver_custom_id', driverId)
            .eq('document_type', docType);

        if (existingDocs.isNotEmpty) {
          final filesToDelete = existingDocs
              .map((doc) => doc['file_path'] as String?)
              .where((path) => path != null && path.isNotEmpty)
              .cast<String>()
              .toList();

          if (filesToDelete.isNotEmpty) {
            await supabase.storage
                .from('driver-documents')
                .remove(filesToDelete);
          }
        }
      } catch (e) {
        print('Error deleting existing file: $e');
      }

      // Upload new file
      await supabase.storage.from('driver-documents').upload(filePath, file);
      final publicUrl = supabase.storage
          .from('driver-documents')
          .getPublicUrl(filePath);

      // Save document record
      final insertData = {
        'driver_custom_id': driverId,
        'document_type': docType,
        'file_url': publicUrl,
        'file_path': filePath,
        'status': 'pending',
        'submitted_at': DateTime.now().toIso8601String(),
        'uploaded_by_role': _userRole == UserRole.agent ? 'agent' : 'driver',
        'document_category': 'personal',
        'user_id': supabase.auth.currentUser?.id, // Add user_id for constraint
      };

      // Add owner information if needed
      if (_userRole == UserRole.agent && _loggedInUserId != null) {
        // For reviewed_by, use the actual auth user ID (UUID), not custom_user_id
        final authUserId = supabase.auth.currentUser?.id;
        if (authUserId != null) {
          insertData['reviewed_by'] = authUserId;
        }
      } else if (_userRole == UserRole.truckOwner && _loggedInUserId != null) {
        insertData['truck_owner_id'] = _loggedInUserId!;
        insertData['owner_custom_id'] = _loggedInUserId!;
      }

      print('About to delete existing document for $driverId - $docType');

      // First, check what documents exist before deleting (check by ALL possible criteria)
      final existingDocsByDriver = await supabase
          .from('driver_documents')
          .select('id, status, file_path, user_id, driver_custom_id')
          .eq('driver_custom_id', driverId)
          .eq('document_type', docType);

      final authUserId = supabase.auth.currentUser?.id;
      List<Map<String, dynamic>> existingDocsByUser = [];
      if (authUserId != null) {
        existingDocsByUser = await supabase
            .from('driver_documents')
            .select('id, status, file_path, user_id, driver_custom_id')
            .eq('user_id', authUserId)
            .eq('document_type', docType);
      }

      print('Current authenticated user ID: $authUserId');
      print('Target driver ID: $driverId');
      print('Existing documents by driver_custom_id: $existingDocsByDriver');
      print('Existing documents by user_id: $existingDocsByUser');

      // Use UPSERT instead of DELETE+INSERT to handle constraint violations
      print('Using UPSERT to handle existing records...');

      // For the unique_user_doc_type constraint, we need to handle conflicts on user_id,document_type
      // But Supabase upsert needs a primary key or unique constraint name
      // Since we can't directly upsert on the constraint, let's try a different approach

      try {
        // First attempt: Try to update existing record (only if we have authUserId)
        List<Map<String, dynamic>> updateResult = [];
        if (authUserId != null) {
          updateResult = await supabase
              .from('driver_documents')
              .update(insertData)
              .eq('user_id', authUserId)
              .eq('document_type', docType)
              .select();
        }

        print('Update attempt result: $updateResult');

        if (updateResult.isEmpty) {
          // No existing record found, try to insert
          print('No existing record found, attempting insert...');
          final insertResult = await supabase
              .from('driver_documents')
              .insert(insertData)
              .select();
          print('Insert result: $insertResult');
        } else {
          print('Successfully updated existing record');
        }
      } catch (e) {
        print('Error during upsert operation: $e');

        // Last resort: Try to force delete and insert with more specific conditions
        try {
          print('Attempting force cleanup...');

          // Try deleting with exact match on all constraint fields
          if (authUserId != null) {
            await supabase
                .from('driver_documents')
                .delete()
                .eq('user_id', authUserId)
                .eq('document_type', docType);
          }

          await supabase
              .from('driver_documents')
              .delete()
              .eq('driver_custom_id', driverId)
              .eq('document_type', docType);

          // Small delay for database consistency
          await Future.delayed(Duration(milliseconds: 100));

          // Try insert again
          final retryInsert = await supabase
              .from('driver_documents')
              .insert(insertData);
          print('Retry insert result: $retryInsert');
        } catch (retryError) {
          print('Force cleanup also failed: $retryError');
          throw retryError;
        }
      } // Add a small delay to ensure database transaction is committed
      await Future.delayed(Duration(milliseconds: 500));

      _showSuccessSnackBar('Document uploaded successfully');
      await _loadDriverDocuments();
    } catch (e) {
      print('Error uploading document: $e');
      _showErrorSnackBar('Error uploading document: ${e.toString()}');
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
      // Get the actual auth user ID (UUID) for reviewed_by field
      final authUserId = supabase.auth.currentUser?.id;

      print('Approving document - Driver: $driverId, DocType: $docType');

      // First, find the most recent document record to update (same logic as in loading)
      final allDocs = await supabase
          .from('driver_documents')
          .select('id, updated_at, status')
          .eq('driver_custom_id', driverId)
          .eq('document_type', docType);

      if (allDocs.isEmpty) {
        _showErrorSnackBar('no_document_found_to_approve'.tr());
        return;
      }

      // Sort by updated_at to get the most recent record
      allDocs.sort((a, b) {
        final aTime =
            DateTime.tryParse(a['updated_at'] ?? '') ?? DateTime(1970);
        final bTime =
            DateTime.tryParse(b['updated_at'] ?? '') ?? DateTime(1970);
        return bTime.compareTo(aTime); // Most recent first
      });

      final mostRecentDoc = allDocs.first;
      final docId = mostRecentDoc['id'];

      print(
        'Updating most recent document with ID: $docId, current status: ${mostRecentDoc['status']}',
      );

      // Use database function to bypass RLS restrictions
      final result = await supabase.rpc(
        'approve_driver_document',
        params: {
          'p_document_id': docId,
          'p_reviewed_by': authUserId,
          'p_reviewed_at': DateTime.now().toIso8601String(),
        },
      );

      print('Approval function result: $result');

      // Check if the function succeeded
      if (result != null && result['success'] == true) {
        print('Document approved successfully via function');
      } else {
        final errorMsg = result?['error'] ?? 'Unknown error';
        throw Exception('Function error: $errorMsg');
      }
      _showSuccessSnackBar('Document approved');
      await _loadDriverDocuments();
    } catch (e) {
      print('Error approving document: $e');
      _showErrorSnackBar('Error approving document: ${e.toString()}');
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
      // Get the actual auth user ID (UUID) for reviewed_by field
      final authUserId = supabase.auth.currentUser?.id;

      print(
        'Rejecting document - Driver: $driverId, DocType: $docType, Reason: $reason',
      );

      // First, find the most recent document record (same logic as in approve)
      final allDocs = await supabase
          .from('driver_documents')
          .select('id, updated_at, status, file_path, file_url')
          .eq('driver_custom_id', driverId)
          .eq('document_type', docType);

      if (allDocs.isEmpty) {
        _showErrorSnackBar('no_document_found_to_reject'.tr());
        return;
      }

      // Sort by updated_at to get the most recent record
      allDocs.sort((a, b) {
        final aTime =
            DateTime.tryParse(a['updated_at'] ?? '') ?? DateTime(1970);
        final bTime =
            DateTime.tryParse(b['updated_at'] ?? '') ?? DateTime(1970);
        return bTime.compareTo(aTime); // Most recent first
      });

      final mostRecentDoc = allDocs.first;
      final docId = mostRecentDoc['id'];
      final existingDoc = mostRecentDoc;

      print(
        'Rejecting most recent document with ID: $docId, current status: ${mostRecentDoc['status']}',
      );

      // Delete the file from storage bucket if it exists
      if (existingDoc['file_path'] != null) {
        final filePath = existingDoc['file_path'] as String;
        print('Deleting file from storage: $filePath');

        try {
          await supabase.storage.from('driver-documents').remove([filePath]);
          print('File deleted successfully from storage');
        } catch (storageError) {
          print('Warning: Could not delete file from storage: $storageError');
          // Continue with database update even if file deletion fails
        }
      }

      // Use database function to bypass RLS restrictions
      final result = await supabase.rpc(
        'reject_driver_document',
        params: {
          'p_document_id': docId,
          'p_reviewed_by': authUserId,
          'p_rejection_reason': reason,
          'p_reviewed_at': DateTime.now().toIso8601String(),
        },
      );

      print('Rejection function result: $result');

      // Check if the function succeeded
      if (result != null && result['success'] == true) {
        print('Document rejected successfully via function');
      } else {
        final errorMsg = result?['error'] ?? 'Unknown error';
        throw Exception('Function error: $errorMsg');
      }
      _showSuccessSnackBar('Document rejected and file deleted');
      await _loadDriverDocuments();
    } catch (e) {
      print('Error rejecting document: $e');
      _showErrorSnackBar('Error rejecting document: ${e.toString()}');
    }
  }

  Future<String?> _showRejectDialog() async {
    String? reason;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title:  Text('reject_document'.tr()),
        content: TextField(
          onChanged: (value) => reason = value,
          decoration:  InputDecoration(
            hintText: 'enter_rejection_reason'.tr(),
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text('cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, reason),
            child:  Text('reject'.tr()),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    String roleText = 'Unknown';
    switch (_userRole) {
      case UserRole.agent:
        roleText = 'Agent';
        break;
      case UserRole.truckOwner:
        roleText = 'Truck Owner';
        break;
      case UserRole.driver:
        roleText = 'Driver';
        break;
      default:
        roleText = 'Unknown';
    }

    return Scaffold(
      appBar: AppBar(
        title:  Text('driver_documents'.tr()),
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (_userRole != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Chip(
                label: Text(
                  roleText,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                backgroundColor: AppColors.teal.withOpacity(0.8),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userRole == UserRole.driver
          ? _buildDriverUploadInterface()
          : Column(
        children: [
          // Status Filter
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  'filter'.tr(),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _statusFilters.map((status) {
                        final isSelected =
                            _selectedStatusFilter == status;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(status),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _selectedStatusFilter = status;
                                _applyStatusFilter();
                              });
                            },
                            backgroundColor: isSelected
                                ? AppColors.teal
                                : null,
                            selectedColor: AppColors.teal,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Drivers List
          Expanded(
            child: ptr.SmartRefresher(
              controller: _refreshController,
              onRefresh: _loadDriverDocuments,
              enablePullDown: true,
              enablePullUp: false,
              header: const ptr.WaterDropHeader(),
              child: _filteredDrivers.isEmpty
                  ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 200),
                  Center(
                    child: Text(
                      'no_drivers_found'.tr(),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              )
                  : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _filteredDrivers.length,
                itemBuilder: (context, index) {
                  final driver = _filteredDrivers[index];
                  return _buildDriverCard(driver);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverCard(Map<String, dynamic> driver) {
    final driverId = driver['custom_user_id'] as String?;
    final driverName = driver['name'] as String? ?? 'Unknown Driver';
    final documents =
        driver['documents'] as Map<String, Map<String, dynamic>>? ?? {};

    if (driverId == null) {
      return const SizedBox.shrink(); // Skip if no valid driver ID
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.teal,
          child: Text(
            driverName.isNotEmpty ? driverName[0].toUpperCase() : 'D',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          driverName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(driverId),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: _personalDocuments.entries.map((entry) {
                final docType = entry.key;
                final docConfig = entry.value;
                final docStatus = documents[docType] ?? {};

                return _buildDocumentTile(
                  driverId,
                  docType,
                  docConfig,
                  docStatus,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentTile(
      String driverId,
      String docType,
      Map<String, dynamic> docConfig,
      Map<String, dynamic> docStatus,
      ) {
    final status = docStatus['status'] ?? 'Not Uploaded';
    final fileUrl = docStatus['file_url'];
    final rejectionReason = docStatus['rejection_reason'];
    final isUploading =
        _uploadingDriverId == driverId && _uploadingDocType == docType;

    // Check upload permission
    bool canUpload = false;
    if (_userRole == UserRole.agent) {
      canUpload = true; // Agents can upload personal documents for drivers
    } else if (_userRole == UserRole.driver && driverId == _loggedInUserId) {
      canUpload = true; // Drivers can upload their own personal documents
    }

    Color statusColor;
    switch (status.toLowerCase()) {
      case 'approved':
        statusColor = Colors.green;
        break;
      case 'rejected':
        statusColor = Colors.red;
        break;
      case 'pending':
        statusColor = Colors.orange;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(docConfig['icon'], color: docConfig['color'], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  docType,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  docConfig['description'],
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (rejectionReason != null && rejectionReason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Reason: $rejectionReason',
                      style: const TextStyle(color: Colors.red, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isUploading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            _buildActionButtons(driverId, docType, status, fileUrl, canUpload),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
      String driverId,
      String docType,
      String status,
      String? fileUrl,
      bool canUpload,
      ) {
    List<Widget> actionButtons = [];

    // Upload/Re-upload button for not uploaded or rejected documents
    if ((status == 'Not Uploaded' || status == 'rejected') && canUpload) {
      actionButtons.add(
        SizedBox(
          height: 32,
          child: ElevatedButton(
            onPressed: () => _uploadDocument(driverId, docType),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              textStyle: const TextStyle(fontSize: 10),
              minimumSize: const Size(60, 32),
            ),
            child: Text(status == 'rejected' ? 'Re-upload' : 'Upload'),
          ),
        ),
      );
    }

    // View button for uploaded documents
    if (status != 'Not Uploaded' && fileUrl != null) {
      actionButtons.add(
        IconButton(
          tooltip: 'view'.tr(),
          icon: Icon(
            Icons.visibility_outlined,
            color: AppColors.teal,
            size: 18,
          ),
          onPressed: () async {
            try {
              final uri = Uri.parse(fileUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            } catch (e) {
              _showErrorSnackBar('Cannot open document');
            }
          },
        ),
      );
    }

    // Approve/Reject buttons for agents and truck owners
    if (status == 'pending' &&
        (_userRole == UserRole.agent || _userRole == UserRole.truckOwner)) {
      actionButtons.addAll([
        IconButton(
          tooltip: 'Approve',
          icon: const Icon(
            Icons.check_circle_outline,
            color: Colors.green,
            size: 18,
          ),
          onPressed: () => _approveDocument(driverId, docType),
        ),
        IconButton(
          tooltip: 'Reject',
          icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
          onPressed: () => _rejectDocument(driverId, docType),
        ),
      ]);
    }

    // Show disabled state for users who can't upload certain documents
    if (status == 'Not Uploaded' && !canUpload) {
      actionButtons.add(
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(4),
          ),
          child:  Text(
            'cannot_upload'.tr(),
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ),
      );
    }

    return Wrap(spacing: 4, children: actionButtons);
  }

  Widget _buildDriverUploadInterface() {
    // Get the driver's own documents
    final driverDocs = _drivers.isNotEmpty
        ? _drivers.first['documents'] as Map<String, Map<String, dynamic>>
        : <String, Map<String, dynamic>>{};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'upload_your_personal_documents'.tr(),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'upload_instruction'.tr(),
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          // Document Upload Cards
          ...(_personalDocuments.entries.map((entry) {
            final docType = entry.key;
            final docName = entry.key; // Use the key as document name
            final docData = driverDocs[docType] ?? {'status': 'Not Uploaded'};
            final status = docData['status'] ?? 'Not Uploaded';
            final rejectionReason = docData['rejection_reason'] as String?;

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _getDocumentIcon(docType),
                          size: 24,
                          color: AppColors.teal,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            docName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _buildStatusChip(status),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (rejectionReason != null && rejectionReason.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red.shade600,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Rejection Reason: $rejectionReason',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (rejectionReason != null && rejectionReason.isNotEmpty)
                      const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Status: $status',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        if (status == 'not_uploaded'.tr() || status == 'rejected'.tr())
                          ElevatedButton.icon(
                            onPressed: _uploadingDriverId != null
                                ? null
                                : () => _uploadDocument(
                              _loggedInUserId!,
                              docType,
                            ),
                            icon:
                            _uploadingDriverId == _loggedInUserId &&
                                _uploadingDocType == docType
                                ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                                : const Icon(Icons.upload_file, size: 16),
                            label: Text(
                              status == 'rejected'.tr() ? 're_upload'.tr() : 'upload'.tr(),
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.teal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                        if (status == 'uploaded' || status == 'pending')
                          Text(
                            'under_review'.tr(),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        if (status == 'approved')
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 16,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'approved'.tr(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }).toList()),
        ],
      ),
    );
  }

  IconData _getDocumentIcon(String docType) {
    switch (docType.toLowerCase()) {
      case 'drivers license':
      case 'driving_license':
        return Icons.badge;
      case 'aadhaar card':
      case 'aadhaar_card':
        return Icons.credit_card;
      case 'pan card':
      case 'pan_card':
        return Icons.business_center;
      case 'profile photo':
      case 'profile_photo':
        return Icons.person;
      default:
        return Icons.description;
    }
  }

  Widget _buildStatusChip(String status) {
    Color backgroundColor;
    Color textColor;

    switch (status.toLowerCase()) {
      case 'approved':
        backgroundColor = Colors.green.shade100;
        textColor = Colors.green.shade800;
        break;
      case 'rejected':
        backgroundColor = Colors.red.shade100;
        textColor = Colors.red.shade800;
        break;
      case 'pending':
      case 'uploaded':
        backgroundColor = Colors.orange.shade100;
        textColor = Colors.orange.shade800;
        break;
      default:
        backgroundColor = Colors.grey.shade100;
        textColor = Colors.grey.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}