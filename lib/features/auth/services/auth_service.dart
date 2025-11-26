import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logging/logging.dart';
import '../utils/user_role.dart';

class AuthService {
  final Logger _logger = Logger('AuthService');
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<UserRole> fetchUserRole(String userId) async {
    try {
      _logger.info('Fetching user role for user: $userId');

      final result = await _fetchSingle('role', userId);
      final role = result as String?;
      if (role == null) throw AuthException('User role not set');

      return _mapStringToUserRole(role);
    } catch (e) {
      _logger.severe('Error fetching user role', e);
      rethrow;
    }
  }

  Future<void> updateUserRole(String userId, UserRole role) async =>
      _runDbAction(
        'Updating user role',
            () => _supabase
            .from('user_profiles')
            .update({'role': role.name})
            .eq('id', userId),
      );

  Future<bool> userProfileExists(String userId) async {
    try {
      final result = await _supabase
          .from('user_profiles')
          .select('id')
          .eq('id', userId)
          .maybeSingle();
      return result != null;
    } catch (e) {
      _logger.warning('Error checking profile existence', e);
      return false;
    }
  }

  Future<void> createUserProfile({
    required String userId,
    required String email,
    required UserRole role,
    Map<String, dynamic>? additionalData,
  }) async {
    final profileData = {
      'id': userId,
      'email': email,
      'role': role.name,
      'created_at': DateTime.now().toIso8601String(),
      ...?additionalData,
    };

    await _runDbAction(
      'Creating user profile',
          () => _supabase.from('user_profiles').insert(profileData),
    );
  }

  Future<dynamic> _fetchSingle(String field, String userId) async {
    final response = await _supabase
        .from('user_profiles')
        .select(field)
        .eq('id', userId)
        .maybeSingle();
    if (response == null) throw AuthException('User profile not found');
    return response[field];
  }

  Future<void> _runDbAction(
      String message,
      Future<void> Function() action,
      ) async {
    try {
      _logger.info(message);
      await action();
      _logger.info('$message success');
    } on PostgrestException catch (e) {
      _logger.severe('Database error: $message', e);
      throw AuthException('Database error: ${e.message}');
    } catch (e) {
      _logger.severe('Unexpected error: $message', e);
      throw AuthException('Failed: $e');
    }
  }

  UserRole _mapStringToUserRole(String input) {
    final roleString = input.toLowerCase();
    if (roleString.contains('driver')) return UserRole.driver;
    if (roleString.contains('truck')) return UserRole.truckOwner;
    if (roleString.contains('shipper')) return UserRole.shipper;
    if (roleString.contains('agent')) return UserRole.agent;

    _logger.warning('Unknown user role: $input');
    throw AuthException('Unknown user role: $input');
  }
}

class AuthException implements Exception {
  final String message;

  const AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}