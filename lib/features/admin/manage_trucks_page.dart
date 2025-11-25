import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:logistics_toolkit/config/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageTrucksPage extends StatefulWidget {
  const ManageTrucksPage({super.key});

  @override
  State<ManageTrucksPage> createState() => _ManageTrucksPageState();
}

class _ManageTrucksPageState extends State<ManageTrucksPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  late Future<List<Map<String, dynamic>>> _trucksFuture;

  @override
  void initState() {
    super.initState();
    _trucksFuture = _fetchTrucks();
  }

  void _showEditDialog(Map<String, dynamic> data) {
    final controllers = {
      'truck_number': TextEditingController(text: data['truck_number']),
      'engine_number': TextEditingController(text: data['engine_number']),
      'chassis_number': TextEditingController(text: data['chassis_number']),
      'vehicle_type': TextEditingController(text: data['vehicle_type']),
      'make': TextEditingController(text: data['make']),
      'model': TextEditingController(text: data['model']),
      'year': TextEditingController(text: data['year']?.toString() ?? ''),
      'capacity_tons': TextEditingController(text: data['capacity_tons']?.toString() ?? ''),
      'fuel_type': TextEditingController(text: data['fuel_type']),
    };

    List<String> fields = [
      'truck_number',
      'engine_number',
      'chassis_number',
      'vehicle_type',
      'make',
      'model',
      'year',
      'capacity_tons',
      'fuel_type'
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("en_route_pickup".tr()),
        content: SingleChildScrollView(
          child: Column(
            children: fields
                .map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: controllers[f],
                decoration: InputDecoration(labelText: f.tr()),
              ),
            ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("cancel".tr()),
          ),
          ElevatedButton(
            onPressed: () async {
              int? parsedYear = int.tryParse(controllers['year']!.text);

              await _updateTruck(
                data['id'],
                controllers['truck_number']!.text,
                controllers['engine_number']!.text,
                controllers['chassis_number']!.text,
                controllers['model']!.text,
                controllers['make']!.text,
                parsedYear,
                controllers['vehicle_type']!.text,
                controllers['capacity_tons']!.text,
                controllers['fuel_type']!.text,
              );

              Navigator.pop(context);
              _refresh();
            },
            child: Text("save".tr()),
          ),
        ],
      ),
    );
  }
  Future<void> _updateTruck(
      int id,
      String number,
      String engine,
      String chassis,
      String model,
      String make,
      int? year,
      String type,
      String tons,
      String fuel,
      ) async {
    try {
      final response = await Supabase.instance.client.rpc(
        'update_truck_details',
        params: {
          'p_truck_id': id,
          'p_truck_number': _v(number),
          'p_engine_number': _v(engine),
          'p_chassis_number': _v(chassis),
          'p_vehicle_type': _v(type),
          'p_make': _v(make),
          'p_model': _v(model),
          'p_year': year,
          'p_capacity_tons': tons.isNotEmpty ? double.tryParse(tons) : null,
          'p_fuel_type': _v(fuel),
        },
      );

      if (response == null || (response as List).isEmpty) {
        throw "No changes applied";
      }

      _msg("Truck updated successfully".tr(), Colors.green);
    } catch (e) {
      _msg("Error updating truck: $e", Colors.red);
    }
  }
  dynamic _v(String v) => v.isEmpty ? null : v;
  Future<List<Map<String, dynamic>>> _fetchTrucks() async {
    final res = await Supabase.instance.client.rpc(
      'get_all_trucks_for_admin',
      params: {'search_query': _searchQuery},
    );
    return res == null ? [] : List<Map<String, dynamic>>.from(res);
  }

  void _msg(String text, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: c));
  }

  Future<void> _refresh() async {
    setState(() => _trucksFuture = _fetchTrucks());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("manage_trucks".tr())),
      body: Column(
        children: [_searchBar(), Expanded(child: _truckList())],
      ),
    );
  }

  Widget _searchBar() => Padding(
    padding: const EdgeInsets.all(8),
    child: TextField(
      controller: _searchController,
      decoration: InputDecoration(
        labelText: 'search_truck'.tr(),
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            _searchController.clear();
            setState(() => _searchQuery = '');
            _refresh();
          },
        ),
      ),
      onChanged: (v) => setState(() => _searchQuery = v),
      onSubmitted: (_) => _refresh(),
    ),
  );

  Widget _truckList() {
    return FutureBuilder(
      future: _trucksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.teal));
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(child: Text("no_trucks_found".tr()));
        }

        final trucks = snapshot.data!;

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            itemCount: trucks.length,
            itemBuilder: (_, i) {
              final t = trucks[i];
              return Card(
                color: Theme.of(context).cardColor,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: Icon(Icons.directions_bus_filled_outlined, color: AppColors.teal),
                  title: Text(
                    t['truck_number'] ?? 'No Number',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    "Owner: ${t['truck_admin'] ?? 'N/A'}\nType: ${t['vehicle_type'] ?? 'N/A'}",
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.edit, color: AppColors.orange),
                    onPressed: () => _showEditDialog(t),
                  ),
                  isThreeLine: true,
                ),
              );
            },
          ),
        );
      },
    );
  }
}