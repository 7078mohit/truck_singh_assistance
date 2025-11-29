import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final SupabaseClient _supabase = Supabase.instance.client;
Future<void> initializeOneSignalAndStorePlayerId() async {
  await OneSignal.Notifications.requestPermission(true);
  OneSignal.User.pushSubscription.addObserver((state) {
    final playerId = state.current.id;
    if (playerId != null) {
      updatePlayerIdInSupabase(playerId);
    }
  });

  final currentId = OneSignal.User.pushSubscription.id;
  if (currentId != null) {
    updatePlayerIdInSupabase(currentId);
  }
}

Future<void> updatePlayerIdInSupabase(String playerId) async {
  try {
    await _supabase.rpc(
      'update_onesignal_player_id',
      params: {'new_player_id': playerId},
    );

    print("✅ OneSignal Player ID updated successfully: $playerId");
  } catch (e) {
    print('❌ Error storing OneSignal Player ID via RPC: $e');
  }
}

Future<void> initializeOneSignalAndStorePlayerIddriver() async {
  final permissionGranted =
  await OneSignal.Notifications.requestPermission(true);

  if (!permissionGranted) return;

  final playerId = OneSignal.User.pushSubscription.id;
  if (playerId != null) {
    try {
      await _supabase.rpc(
        'update_onesignal_player_id',
        params: {'new_player_id': playerId},
      );
      print("✅ OneSignal Player ID for driver stored successfully via RPC.");
    } catch (e) {
      print('❌ Error storing driver OneSignal Player ID via RPC: $e');
    }
  }
}