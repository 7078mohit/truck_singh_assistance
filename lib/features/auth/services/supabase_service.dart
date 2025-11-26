import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/user_role.dart';

class SupabaseService {
  static final SupabaseClient client = Supabase.instance.client;

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
      await client.from('user_profiles').upsert({
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
      print('Error saving user profile: $e');
      return false;
    }
  }

  static Future<UserRole?> getUserRole(String userId) async {
    try {
      final response = await client
          .from('user_profiles')
          .select('role')
          .eq('user_id', userId)
          .single();

      final roleString = response['role'] as String?;
      return roleString == null
          ? null
          : UserRole.values.firstWhere(
            (role) => role.dbValue == roleString,
        orElse: () => UserRole.driver,
      );
    } catch (e) {
      print('Error getting user role: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getUserProfile(String userId) async =>
      _safeFetch(
            () => client
            .from('user_profiles')
            .select()
            .eq('user_id', userId)
            .single(),
      );

  static Future<bool> isProfileCompleted(String userId) async {
    try {
      final res = await client
          .from('user_profiles')
          .select('profile_completed')
          .eq('user_id', userId)
          .single();
      return res['profile_completed'] ?? false;
    } catch (e) {
      print('Error checking profile completion: $e');
      return false;
    }
  }

  static User? getCurrentUser() => client.auth.currentUser;

  static Future<User?> signInWithEmail(String email, String password) async =>
      _safeAuth(
            () => client.auth.signInWithPassword(email: email, password: password),
      );

  static Future<User?> signUpWithEmail(String email, String password) async =>
      _safeAuth(() => client.auth.signUp(email: email, password: password));

  static Future<void> signOut() async => client.auth.signOut();

  static Future<String?> getCustomUserId(String userId) async {
    try {
      final res = await client
          .from('user_profiles')
          .select('custom_user_id')
          .eq('user_id', userId)
          .single();
      return res['custom_user_id'] as String?;
    } catch (e) {
      print('Error getting custom user ID: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _safeFetch(
      Future<Map<String, dynamic>> Function() run,
      ) async {
    try {
      return await run();
    } catch (e) {
      print('Supabase fetch error: $e');
      return null;
    }
  }

  static Future<User?> _safeAuth(Future<AuthResponse> Function() run) async {
    try {
      return (await run()).user;
    } catch (e) {
      print('Auth error: $e');
      return null;
    }
  }
}