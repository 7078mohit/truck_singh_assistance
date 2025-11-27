import 'package:flutter_bloc/flutter_bloc.dart';
import '/services/shipment_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'shipment_state.dart';

class ShipmentCubit extends Cubit<ShipmentState> {
  ShipmentCubit() : super(const ShipmentState());

  /// Fetches available shipments from the service.
  Future<void> fetchAvailableShipments() async {
    emit(state.copyWith(status: ShipmentStatus.loading));

    try {
      final shipments =
      await ShipmentService.getAvailableMarketplaceShipments();

      emit(state.copyWith(
        status: ShipmentStatus.success,
        shipments: shipments,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: ShipmentStatus.failure,
        errorMessage: 'fetch_shipments_error'
            .tr(namedArgs: {'error': e.toString()}),
      ));
    }
  }

  /// Accepts a shipment and then refreshes the shipment list from backend.
  Future<void> acceptShipment({required String shipmentId}) async {
    try {
      await ShipmentService.acceptMarketplaceShipment(
        shipmentId: shipmentId,
      );
      await fetchAvailableShipments();
    } catch (e) {
      emit(state.copyWith(
        status: ShipmentStatus.failure,
        errorMessage: 'accept_shipment_error'
            .tr(namedArgs: {'error': e.toString()}),
      ));
    }
  }
}