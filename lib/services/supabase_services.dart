import 'package:logistics_toolkit/features/auth/utils/user_role.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();
  static final SupabaseClient _client = Supabase.instance.client;
  static SupabaseClient get client => _client;

  static Future<bool> saveUserProfile({
    required String customUserId,
    required String userId,
    required UserRole role,
    required String name,
    required String dateOfBirth,
    required String mobileNumber,
    String? email,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      await _client.from('user_profiles').upsert({
        'user_id': userId,
        'custom_user_id': customUserId,
        'role': role.dbValue,
        'name': name,
        'date_of_birth': dateOfBirth,
        'mobile_number': mobileNumber,
        'email': email,
        'profile_completed': true,
        'updated_at': DateTime.now().toIso8601String(),
        ...?additionalData,
      });
      return true;
    } catch (e) {
      print('❌ Error saving user profile: $e');
      return false;
    }
  }

  static Future<UserRole?> getUserRole(String userId) async {
    try {
      final res = await _client
          .from('user_profiles')
          .select('role')
          .eq('user_id', userId)
          .maybeSingle();

      final roleValue = res?['role'];
      if (roleValue == null) return null;

      return UserRole.values.firstWhere(
            (r) => r.dbValue == roleValue,
        orElse: () => UserRole.driver,
      );
    } catch (e) {
      print('❌ Error getting user role: $e');
      return null;
    }
  }

  static Future<String?> getCustomUserId(String userId) async {
    try {
      final res = await _client
          .from('user_profiles')
          .select('custom_user_id')
          .eq('user_id', userId)
          .maybeSingle();

      return res?['custom_user_id'];
    } catch (e) {
      print('❌ Error getting custom user ID: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      return await _client
          .from('user_profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
    } catch (e) {
      print('❌ Error getting user profile: $e');
      return null;
    }
  }

  static Future<bool> isProfileCompleted(String userId) async {
    try {
      final res = await _client
          .from('user_profiles')
          .select('profile_completed')
          .eq('user_id', userId)
          .maybeSingle();

      return res?['profile_completed'] ?? false;
    } catch (e) {
      print('❌ Error checking profile completion: $e');
      return false;
    }
  }

  static User? getCurrentUser() => _client.auth.currentUser;

  static Future<User?> signInWithEmail(String email, String password) async {
    try {
      final result = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return result.user;
    } catch (e) {
      print('❌ Sign-in error: $e');
      return null;
    }
  }

  static Future<User?> signUpWithEmail(String email, String password) async {
    try {
      final result = await _client.auth.signUp(
        email: email,
        password: password,
      );
      return result.user;
    } catch (e) {
      print('❌ Sign-up error: $e');
      return null;
    }
  }

  static Future<void> signOut() async => _client.auth.signOut();
}