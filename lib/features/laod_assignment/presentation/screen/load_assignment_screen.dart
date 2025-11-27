import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubits/shipment_cubit.dart';
import '../cubits/shipment_state.dart';
import '../widgets/shipment_list_view.dart';
import 'package:easy_localization/easy_localization.dart';

class LoadAssignmentScreen extends StatefulWidget {
  const LoadAssignmentScreen({super.key});

  @override
  State<LoadAssignmentScreen> createState() => _LoadAssignmentScreenState();
}

class _LoadAssignmentScreenState extends State<LoadAssignmentScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ShipmentCubit()..fetchAvailableShipments(),
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          title: Text('shipment_marketplace'.tr()),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextField(
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'search_hint'.tr(),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        ),

        body: SafeArea(
          child: BlocConsumer<ShipmentCubit, ShipmentState>(
            listener: (context, state) {
              if (state.status == ShipmentStatus.failure &&
                  state.errorMessage != null) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(content: Text(state.errorMessage!)),
                  );
              }
            },

            builder: (context, state) {
              return RefreshIndicator(
                onRefresh: () =>
                    context.read<ShipmentCubit>().fetchAvailableShipments(),
                child: _buildBody(context, state),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ShipmentState state) {
    switch (state.status) {
      case ShipmentStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case ShipmentStatus.failure:
        if (state.shipments.isEmpty) {
          return Center(
            child: Text(state.errorMessage ?? 'unknown_error'.tr()),
          );
        }
        return ShipmentListView(
          shipments: state.shipments,
          searchQuery: _searchQuery,
        );

      case ShipmentStatus.success:
      default:
        if (state.shipments.isEmpty) {
          return Center(child: Text('no_shipments'.tr()));
        }
        return ShipmentListView(
          shipments: state.shipments,
          searchQuery: _searchQuery,
        );
    }
  }
}