import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserDataService {
  UserDataService._();

  static const _cacheKey = 'custom_user_id';
  static String? _cachedId;
  static Future<String?> getCustomUserId() async {
    if (_cachedId != null) return _cachedId;

    final prefs = await SharedPreferences.getInstance();
    final storedId = prefs.getString(_cacheKey);

    if (storedId != null) {
      _cachedId = storedId;
      return storedId;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      print('⚠ getCustomUserId: No authenticated user.');
      return null;
    }

    try {
      final result = await Supabase.instance.client
          .from('user_profiles')
          .select('custom_user_id')
          .eq('user_id', user.id)
          .maybeSingle(); // safer than .single()

      final customId = result?['custom_user_id'];

      if (customId != null) {
        _cachedId = customId;
        await prefs.setString(_cacheKey, customId);
      }

      return customId;
    } catch (e) {
      print('❌ Error retrieving custom_user_id: $e');
      return null;
    }
  }
  /// Clears both memory + shared storage cache
  static Future<void> clearCache() async {
    _cachedId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }
}