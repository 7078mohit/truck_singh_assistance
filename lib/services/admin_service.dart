import 'package:supabase_flutter/supabase_flutter.dart';

class AdminService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Debug function to check current user admin status
  static Future<Map<String, dynamic>> debugCurrentUserStatus() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        return {'logged_in': false, 'error': 'No user logged in'};
      }

      final profile = await _supabase
          .from('user_profiles')
          .select('custom_user_id, role, email, name')
          .eq('user_id', currentUser.id)
          .maybeSingle();

      return {
        'logged_in': true,
        'user_id': currentUser.id,
        'email': currentUser.email,
        'profile': profile,
        'is_admin': profile?['role']?.toString().toLowerCase() == 'admin',
      };
    } catch (e) {
      return {'logged_in': false, 'error': e.toString()};
    }
  }

  /// Check if current user is admin
  static Future<bool> isCurrentUserAdmin() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        print('🐛 Admin Check: No current user');
        return false;
      }

      final profile = await _supabase
          .from('user_profiles')
          .select('role, custom_user_id')
          .eq('user_id', currentUser.id)
          .maybeSingle();

      print('🔍 Admin Check Profile: $profile');

      final role = profile?['role']?.toString().toLowerCase();
      final customId = profile?['custom_user_id']?.toString();

      final isAdmin = role == 'admin';
      final isAgentWithAdminPerms =
          role == 'agent' && customId?.startsWith('AGNT') == true;

      print(
        '🔍 Admin Check Result: isAdmin=$isAdmin, isAgentWithPerms=$isAgentWithAdminPerms',
      );

      return isAdmin || isAgentWithAdminPerms;
    } catch (e) {
      print('🐛 Admin Check: Error checking admin status: $e');
      return false;
    }
  }

  /// Create admin user - consolidated version with session preservation
  static Future<Map<String, dynamic>> createAdminUser({
    required String email,
    required String password,
    String? name,
    required dynamic dateOfBirth,
    required dynamic mobileNumber,
  }) async {
    try {
      final String dateOfBirthStr = dateOfBirth is String
          ? dateOfBirth
          : (dateOfBirth is int
          ? DateTime.fromMillisecondsSinceEpoch(dateOfBirth).toIso8601String()
          : DateTime(1990, 1, 1).toIso8601String());

      final String mobileNumberStr =
      mobileNumber is String ? mobileNumber : mobileNumber.toString();

      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        throw Exception(
            'No user is currently logged in. Please log in as an admin first.');
      }

      final currentUserId = currentUser.id;
      final currentUserEmail = currentUser.email;

      final creatorProfile = await _supabase
          .from('user_profiles')
          .select('custom_user_id, role')
          .eq('user_id', currentUserId)
          .maybeSingle();

      String? creatorAdminId = creatorProfile?['custom_user_id'];
      final creatorRole = creatorProfile?['role']?.toString();

      final isAdmin = creatorRole?.toLowerCase() == 'admin';
      final isAgentWithAdminPerms =
          creatorRole?.toLowerCase() == 'agent' &&
              creatorAdminId?.startsWith('AGNT') == true;

      if (!isAdmin && !isAgentWithAdminPerms) {
        throw Exception(
            'Access denied: Only admins can create admin users. Your role: $creatorRole');
      }

      if (creatorAdminId == null && currentUserEmail == 'admin@gmail.com') {
        creatorAdminId = 'ADM5478';
      }

      if (creatorAdminId == null) {
        throw Exception(
            'Creator admin profile not found. Please ensure you are logged in as an admin.');
      }

      final existingUser = await _supabase
          .from('user_profiles')
          .select('email, custom_user_id')
          .eq('email', email)
          .maybeSingle();

      if (existingUser != null) {
        throw Exception(
            'User with email $email already exists (ID: ${existingUser['custom_user_id']})');
      }

      String customUserId;
      int attempts = 0;
      do {
        final random = DateTime.now().millisecond +
            DateTime.now().second * 1000 +
            attempts;
        final shortId = (random % 10000).toString().padLeft(4, '0');

        customUserId = 'ADM$shortId';

        final exists = await _supabase
            .from('user_profiles')
            .select('custom_user_id')
            .eq('custom_user_id', customUserId)
            .maybeSingle();

        if (exists == null) break;
        attempts++;
      } while (attempts < 10);

      if (attempts >= 10) {
        throw Exception('Failed to generate unique admin ID after 10 attempts');
      }

      try {
        final adminResponse = await _supabase.auth.admin.createUser(
          AdminUserAttributes(
            email: email,
            password: password,
            emailConfirm: true,
            userMetadata: {
              'name': name ?? 'Admin User',
              'role': 'Admin',
              'custom_user_id': customUserId,
            },
          ),
        );

        if (adminResponse.user != null) {
          final newUserId = adminResponse.user!.id;

          await _createUserProfile(
            userId: newUserId,
            customUserId: customUserId,
            email: email,
            name: name,
            creatorAdminId: creatorAdminId,
            dateOfBirth: dateOfBirthStr,
            mobileNumber: mobileNumberStr,
          );

          return {
            'success': true,
            'admin_id': customUserId,
            'creator_id': creatorAdminId,
            'message':
            'Admin $customUserId created successfully! You remain logged in.',
            'requires_reauth': false,
            'method': 'admin_api',
          };
        }
      } catch (_) {}

      return await _createWithSessionPreservation(
        email: email,
        password: password,
        name: name,
        customUserId: customUserId,
        creatorAdminId: creatorAdminId,
        currentUserEmail: currentUserEmail,
        dateOfBirth: dateOfBirthStr,
        mobileNumber: mobileNumberStr,
      );
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'requires_reauth': false,
      };
    }
  }

  /// Create profile helper
  static Future<void> _createUserProfile({
    required String userId,
    required String customUserId,
    required String email,
    String? name,
    required String creatorAdminId,
    String? dateOfBirth,
    String? mobileNumber,
  }) async {
    final data = {
      'user_id': userId,
      'custom_user_id': customUserId,
      'email': email,
      'role': 'Admin',
      'name': name ?? 'Admin User',
      'date_of_birth': dateOfBirth ?? DateTime(1990, 1, 1).toIso8601String(),
      'mobile_number': mobileNumber ?? '0000000000',
      'account_disable': false,
      'profile_completed': true,
      'created_by_admin_id': creatorAdminId,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    await _supabase.from('user_profiles').insert(data);
  }

  /// Fallback session-preserving user creation
  static Future<Map<String, dynamic>> _createWithSessionPreservation({
    required String email,
    required String password,
    String? name,
    required String customUserId,
    required String creatorAdminId,
    required String? currentUserEmail,
    required String dateOfBirth,
    required String mobileNumber,
  }) async {
    final currentSession = _supabase.auth.currentSession;
    if (currentSession == null) {
      throw Exception('No active session to preserve');
    }

    final refreshToken = currentSession.refreshToken;

    try {
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (authResponse.user == null) {
        throw Exception('Failed to create user account');
      }

      final newUserId = authResponse.user!.id;

      await _createUserProfile(
        userId: newUserId,
        customUserId: customUserId,
        email: email,
        name: name,
        creatorAdminId: creatorAdminId,
        dateOfBirth: dateOfBirth,
        mobileNumber: mobileNumber,
      );

      await _supabase.auth.signOut();

      if (refreshToken != null) {
        final restore = await _supabase.auth.setSession(refreshToken);

        if (restore.session?.user.email?.toLowerCase() ==
            currentUserEmail?.toLowerCase()) {
          return {
            'success': true,
            'admin_id': customUserId,
            'creator_id': creatorAdminId,
            'message':
            'Admin $customUserId created successfully! You remain logged in.',
            'requires_reauth': false,
            'method': 'session_restore',
          };
        }
      }

      return {
        'success': true,
        'admin_id': customUserId,
        'creator_id': creatorAdminId,
        'message':
        'Admin $customUserId created successfully, but you were logged out.',
        'requires_reauth': true,
        'method': 'session_restore_failed',
      };
    } catch (e) {
      throw Exception('Failed to create admin with session preservation: $e');
    }
  }

  /// Get all users created by this admin
  static Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final profile = await _supabase
          .from('user_profiles')
          .select('custom_user_id, role')
          .eq('user_id', currentUser.id)
          .maybeSingle();

      if (profile == null) throw Exception('Admin profile not found');

      final adminId = profile['custom_user_id'];

      final users = await _supabase
          .from('user_profiles')
          .select('*')
          .eq('created_by_admin_id', adminId)
          .eq('role', 'Admin')
          .order('created_at', ascending: false);

      final Map<String, Map<String, dynamic>> unique = {};
      for (final user in users) {
        final email = user['email']?.toString().toLowerCase();
        if (email != null) {
          if (!unique.containsKey(email) ||
              DateTime.parse(user['created_at'])
                  .isAfter(DateTime.parse(unique[email]!['created_at']))) {
            unique[email] = user;
          }
        }
      }

      return unique.values.toList();
    } catch (e) {
      throw Exception('Failed to fetch users: $e');
    }
  }
}