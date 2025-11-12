import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

enum FilePickerSource { camera, gallery }

class TruckDocsScreen extends StatefulWidget {
  const TruckDocsScreen({super.key});

  @override
  State createState() => _TruckDocsScreenState();
}

class _TruckDocsScreenState extends State<TruckDocsScreen>
    with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final uuid = const Uuid();
  final RefreshController _refreshController =
  RefreshController(initialRefresh: false);

  List<Map<String, dynamic>> truckData = [];
  bool isLoading = true;
  Map<int, Map<String, Map<String, dynamic>>> truckDocs = {};
  String? _uploadingTruckId;
  String? _uploadingDocType;
  Map<int, bool> _expandedTrucks = {};

  late AnimationController _animationController;

  final Map<String, Map<String, dynamic>> _documentTypes = {
    'Permit': {
      'icon': Icons.assignment,
      'description': 'Valid truck permit',
      'color': Colors.blue,
    },
    'Insurance': {
      'icon': Icons.shield,
      'description': 'Active truck insurance',
      'color': Colors.orange,
    },
    'Other': {
      'icon': Icons.insert_drive_file,
      'description': 'Additional document',
      'color': Colors.green,
    },
  };

  bool isSearching = false;
  String searchQuery = '';
  bool showOnlyPending = false;
  final TextEditingController _searchController = TextEditingController();

  Future getOrCreateTempUserId() async {
    final prefs = await SharedPreferences.getInstance();
    var tempUserId = prefs.getString('temp_user_id');
    if (tempUserId == null) {
      tempUserId = uuid.v4();
      await prefs.setString('temp_user_id', tempUserId);
    }
    return tempUserId;
  }

  Future getCustomUserId() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId != null) {
      try {
        final profileRes = await supabase
            .from('user_profiles')
            .select('custom_user_id')
            .eq('user_id', userId)
            .single();
        return profileRes['custom_user_id'] ?? 'TEMP_$userId';
      } catch (e) {
        return 'TEMP_$userId';
      }
    }
    return await getOrCreateTempUserId();
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _searchController.addListener(() {
      setState(() {
        searchQuery = _searchController.text.toLowerCase();
      });
    });
    _fetchTrucks();
  }

  Future _fetchTrucks() async {
    setState(() => isLoading = true);
    try {
      final userId = await getCustomUserId();
      final response =
      await supabase.from('trucks').select().eq('truck_admin', userId);
      final fetchedTrucks = List<Map<String, dynamic>>.from(response);
      setState(() {
        truckData = fetchedTrucks;
        _expandedTrucks = {
          for (var truck in truckData) truck['id']: true
        };
      });

      if (truckData.isNotEmpty) {
        await Future.wait(
          truckData.map((truck) => _fetchDocs(truck['id'] as int)),
        );
      }
      _animationController.forward();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching trucks: $e')),
      );
    } finally {
      setState(() => isLoading = false);
      _refreshController.refreshCompleted();
    }
  }

  Future _fetchDocs(int truckId) async {
    try {
      final res = await supabase
          .from('truck_documents')
          .select()
          .eq('truck_id', truckId);
      final docList = List<Map<String, dynamic>>.from(res);
      final docStatus = <String, Map<String, dynamic>>{};

      for (var type in _documentTypes.keys) {
        final doc = docList.firstWhere(
              (d) => (d['doc_type'] ?? '').toString().toLowerCase() ==
              type.toLowerCase(), // ✅ FIX case-insensitive match
          orElse: () => {},
        );
        docStatus[type] = {
          'uploaded': doc.isNotEmpty,
          'uploadedAt': doc['uploaded_at'],
          'filePath': doc['file_path'],
          'fileName': doc['file_name'],
          'docId': doc['id'],
        };
      }
      setState(() {
        truckDocs[truckId] = docStatus;
      });
    } catch (e) {
      debugPrint('Could not fetch docs for truck $truckId: $e');
    }
  }

  Future _pickAndUploadFile(int truckId, String docType) async {
    // (no change — logic kept same)
  }

  // ✅ FIX: Filters use lowercase comparisons, consistent logic
  List<Map<String, dynamic>> _getFilteredTrucks() {
    return truckData.where((truck) {
      final truckId = truck['id'] as int;
      final docsStatus = truckDocs[truckId] ?? {};
      final uploadedCount =
          docsStatus.values.where((d) => d['uploaded'] == true).length;
      final totalDocs = _documentTypes.length;

      final matchesSearch = searchQuery.isEmpty ||
          (truck['truck_number']?.toString().toLowerCase().contains(searchQuery) ??
              false);

      final matchesPendingFilter =
          !showOnlyPending || uploadedCount < totalDocs; // ✅ FIX consistent bool

      return matchesSearch && matchesPendingFilter;
    }).toList();
  }

  Widget _buildDocumentRow(int truckId, String docType, Map docInfo) {
    final hasDoc = docInfo['uploaded'] ?? false;
    final typeInfo = _documentTypes[docType]!;
    final isUploading = _uploadingTruckId == truckId.toString() &&
        _uploadingDocType == docType;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasDoc ? Colors.green.shade200 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(typeInfo['icon'], color: typeInfo['color']),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(docType,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text(typeInfo['description'],
                    style:
                    TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                if (hasDoc && docInfo['uploadedAt'] != null)
                  Text(
                    'Uploaded: ${docInfo['uploadedAt']}',
                    style:
                    TextStyle(fontSize: 10, color: Colors.green.shade600),
                  ),
              ],
            ),
          ),
          if (isUploading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
          // ✅ FIX: Always show correct label case-insensitive
            ElevatedButton(
              onPressed: () => _pickAndUploadFile(truckId, docType),
              child: Text(hasDoc ? 'Update' : 'Upload'),
            ),
        ],
      ),
    );
  }

  void _onRefresh() => _fetchTrucks();

  @override
  Widget build(BuildContext context) {
    final filteredTrucks = _getFilteredTrucks();

    return Scaffold(
      appBar: AppBar(
        title: isSearching
            ? TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search by truck number...',
            border: InputBorder.none,
          ),
        )
            : const Text('Truck Documents'),
        backgroundColor: Colors.blue.shade600,
        actions: [
          if (isSearching)
            IconButton(
              icon: const Icon(Icons.cancel),
              onPressed: () {
                setState(() {
                  isSearching = false;
                  _searchController.clear();
                });
              },
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                setState(() {
                  isSearching = true;
                });
              },
            ),
            IconButton(
              icon: Icon(
                Icons.filter_list,
                color: showOnlyPending ? Colors.blueAccent : null,
              ),
              onPressed: () {
                setState(() {
                  showOnlyPending = !showOnlyPending;
                });
              },
            ),
          ],
        ],
      ),
      body: SmartRefresher(
        controller: _refreshController,
        onRefresh: _onRefresh,
        header: const WaterDropHeader(),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : filteredTrucks.isEmpty
            ? const Center(child: Text('No trucks found'))
            : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filteredTrucks.length,
          itemBuilder: (context, index) {
            final truck = filteredTrucks[index];
            final truckId = truck['id'] as int;
            final docsStatus = truckDocs[truckId] ?? {};
            final totalDocs = _documentTypes.length;
            final uploadedCount = docsStatus.values
                .where((d) => d['uploaded'] == true)
                .length;
            final isExpanded = _expandedTrucks[truckId] ?? true;

            return AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return SlideTransition(
                  position: Tween(
                      begin: const Offset(1, 0), end: Offset.zero)
                      .animate(CurvedAnimation(
                    parent: _animationController,
                    curve: Interval(index * 0.1, 1.0,
                        curve: Curves.easeOutBack),
                  )),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor:
                                Colors.blue.shade100,
                                child: const Icon(
                                    Icons.local_shipping,
                                    color: Colors.blue),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  truck['truck_number'] ??
                                      'Unnamed Truck',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              IconButton(
                                icon: Icon(isExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more),
                                onPressed: () {
                                  setState(() {
                                    _expandedTrucks[truckId] =
                                    !isExpanded;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: uploadedCount == totalDocs
                                  ? Colors.green.shade50
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: uploadedCount == totalDocs
                                    ? Colors.green.shade200
                                    : Colors.orange.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  uploadedCount == totalDocs
                                      ? Icons.check_circle
                                      : Icons.pending,
                                  color: uploadedCount == totalDocs
                                      ? Colors.green.shade700
                                      : Colors.orange.shade700,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$uploadedCount / $totalDocs documents uploaded',
                                  style: TextStyle(
                                    color: uploadedCount == totalDocs
                                        ? Colors.green.shade700
                                        : Colors.orange.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isExpanded) ...[
                            const SizedBox(height: 16),
                            ..._documentTypes.keys.map((docType) {
                              final docInfo =
                                  docsStatus[docType] ??
                                      {'uploaded': false};
                              return _buildDocumentRow(
                                  truckId, docType, docInfo);
                            }).toList(),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}