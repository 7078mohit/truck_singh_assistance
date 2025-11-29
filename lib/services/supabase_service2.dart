import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/auth/utils/user_role.dart';

class SupabaseService2 {
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
        if (additionalData != null) ...additionalData,
      });
      return true;
    } catch (e) {
      print('Error saving user profile: $e');
      return false;
    }
  }

  static Future<UserRole?> getUserRole(String userId) async {
    try {
      final response = await _client
          .from('user_profiles')
          .select('role')
          .eq('user_id', userId)
          .single();

      final roleString = response['role'] as String?;
      if (roleString == null) return null;

      return UserRole.values.firstWhere(
            (role) => role.dbValue == roleString,
        orElse: () => UserRole.driver,
      );
    } catch (e) {
      print('Error getting user role: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await _client
          .from('user_profiles')
          .select()
          .eq('user_id', userId)
          .single();
      return response;
    } catch (e) {
      print('Error getting user profile: $e');
      return null;
    }
  }

  static Future<bool> isProfileCompleted(String userId) async {
    try {
      final response = await _client
          .from('user_profiles')
          .select('profile_completed')
          .eq('user_id', userId)
          .single();
      return response['profile_completed'] ?? false;
    } catch (e) {
      print('Error checking profile completion: $e');
      return false;
    }
  }

  static User? getCurrentUser() {
    return _client.auth.currentUser;
  }

  static Future<User?> signInWithEmail(String email, String password) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response.user;
    } catch (e) {
      print('Error signing in: $e');
      return null;
    }
  }

  static Future<User?> signUpWithEmail(String email, String password) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
      );
      return response.user;
    } catch (e) {
      print('Error signing up: $e');
      return null;
    }
  }

  static Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // Account Disable/Enable Functions - Direct Table Operations
  static Future<Map<String, dynamic>> setAccountDisable({
    required String targetCustomId,
    required bool disable,
    required String performedByUserId,
  }) async {
    try {
      // Get target user profile
      final targetResponse = await _client
          .from('user_profiles')
          .select('*')
          .eq('custom_user_id', targetCustomId)
          .maybeSingle();

      if (targetResponse == null) {
        return {'ok': false, 'error': 'target_not_found'};
      }

      // Get performer user profile
      final performerResponse = await _client
          .from('user_profiles')
          .select('*')
          .eq('user_id', performedByUserId)
          .maybeSingle();

      if (performerResponse == null) {
        return {'ok': false, 'error': 'performer_not_found'};
      }
      final isSameUser =
          performerResponse['user_id'] == targetResponse['user_id'];
      final isAuthorizedOwner =
          (performerResponse['role'] == 'truckowner' ||
              performerResponse['role'] == 'agent') &&
              targetResponse['truck_owner_id'] ==
                  performerResponse['custom_user_id'];

      if (!isSameUser && !isAuthorizedOwner) {
        return {'ok': false, 'error': 'not_authorized'};
      }
      if (disable) {
        final activeShipmentsResponse = await _client
            .from('shipment')
            .select('id, booking_status')
            .eq('assigned_driver', targetCustomId)
            .neq('booking_status', 'Completed')
            .neq('booking_status', 'Cancelled');

        if (activeShipmentsResponse.isNotEmpty) {
          return {
            'ok': false,
            'error': 'driver_has_active_shipment',
            'active_count': activeShipmentsResponse.length,
          };
        }
      }
      final currentLogs = targetResponse['account_status_logs'] as List? ?? [];
      final logEntry = {
        'timestamp': DateTime.now().toIso8601String(),
        'performed_by': performerResponse['custom_user_id'],
        'action': disable ? 'disabled' : 'enabled',
        'reason': 'manual_action',
      };

      // Update account status
      await _client
          .from('user_profiles')
          .update({
        'account_disable': disable,
        'account_status_logs': [...currentLogs, logEntry],
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('custom_user_id', targetCustomId);

      return {
        'ok': true,
        'message': disable
            ? 'Account disabled successfully'
            : 'Account enabled successfully',
        'target_user': targetCustomId,
      };
    } catch (e) {
      print('Error setting account disable status: $e');
      return {'ok': false, 'error': 'network_error', 'details': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> requestAccountActivation({
    required String requesterCustomId,
  }) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount <= maxRetries) {
      try {
        print(
          'Requesting account activation for: $requesterCustomId (attempt ${retryCount + 1})',
        );
        final requesterResponse = await _client
            .from('user_profiles')
            .select('*')
            .eq('custom_user_id', requesterCustomId)
            .maybeSingle()
            .timeout(
          const Duration(seconds: 10),
          onTimeout: () =>
          throw Exception('Timeout: Failed to get requester profile'),
        );

        if (requesterResponse == null) {
          return {'ok': false, 'error': 'requester_not_found'};
        }
        if (requesterResponse['account_disable'] != true) {
          return {'ok': false, 'error': 'account_not_disabled'};
        }
        final ownerCustomId = requesterResponse['truck_owner_id'];
        if (ownerCustomId == null) {
          return {'ok': false, 'error': 'no_associated_owner'};
        }
        final ownerResponse = await _client
            .from('user_profiles')
            .select('user_id')
            .eq('custom_user_id', ownerCustomId)
            .maybeSingle()
            .timeout(
          const Duration(seconds: 10),
          onTimeout: () =>
          throw Exception('Timeout: Failed to get owner profile'),
        );

        if (ownerResponse == null) {
          return {'ok': false, 'error': 'owner_not_found'};
        }
        final notificationResponse = await _client
            .from('notifications')
            .insert({
          'user_id': ownerResponse['user_id'],
          'title': 'Account Activation Request',
          'message':
          '${requesterResponse['name']} (${requesterResponse['custom_user_id']}) is requesting to activate their account',
          'type': 'account_activation_request',
          'related_id': requesterResponse['custom_user_id'],
          'data': {
            'requester_custom_id': requesterResponse['custom_user_id'],
            'requester_name': requesterResponse['name'],
            'requester_role': requesterResponse['role'],
            'request_timestamp': DateTime.now().toIso8601String(),
          },
          'created_at': DateTime.now().toIso8601String(),
          'is_read': false,
        })
            .select('id')
            .single()
            .timeout(
          const Duration(seconds: 15),
          onTimeout: () =>
          throw Exception('Timeout: Failed to create notification'),
        );

        print('Account activation request sent successfully');
        return {
          'ok': true,
          'message': 'Activation request sent successfully',
          'notification_id': notificationResponse['id'],
          'sent_to': ownerCustomId,
        };
      } catch (e) {
        retryCount++;
        print('Error requesting account activation (attempt $retryCount): $e');
        if (retryCount > maxRetries) {
          String errorType = 'network_error';
          if (e.toString().contains('Timeout')) {
            errorType = 'timeout_error';
          }
          return {
            'ok': false,
            'error': errorType,
            'details': e.toString(),
            'retries_attempted': retryCount - 1,
          };
        }
        await Future.delayed(Duration(seconds: retryCount * 2));
      }
    }

    return {'ok': false, 'error': 'max_retries_exceeded'};
  }

  static Future<Map<String, dynamic>> getUserProfileWithStatus({
    required String userId,
  }) async {
    try {
      final response = await _client
          .from('user_profiles')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        return {'ok': false, 'error': 'user_not_found'};
      }

      return {
        'ok': true,
        'profile': response,
        'account_disabled': response['account_disable'] ?? false,
      };
    } catch (e) {
      print('Error getting user profile with status: $e');
      return {'ok': false, 'error': 'network_error', 'details': e.toString()};
    }
  }
  static Future<String?> getCustomUserId(String userId) async {
    try {
      final response = await _client
          .from('user_profiles')
          .select('custom_user_id')
          .eq('user_id', userId)
          .single();

      return response['custom_user_id'] as String?;
    } catch (e) {
      print('Error getting custom user ID: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> getDriversUnderOwner({
    required String ownerCustomId,
  }) async {
    try {
      final response = await _client
          .from('user_profiles')
          .select(
        'custom_user_id, name, role, account_disable, mobile_number, email, profile_picture, created_at',
      )
          .eq('truck_owner_id', ownerCustomId)
          .ilike('role', 'driver_%');

      return {'ok': true, 'drivers': response};
    } catch (e) {
      print('Error getting drivers under owner: $e');
      return {'ok': false, 'error': 'network_error', 'details': e.toString()};
    }
  }
}