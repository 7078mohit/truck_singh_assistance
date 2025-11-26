import 'package:supabase_flutter/supabase_flutter.dart';
import '../notifications/notification_manager.dart';

class AccountReactivationService {
  static final supabase = Supabase.instance.client;
  static Future<Map<String, dynamic>?> getAccountDisableInfo({
    required String customUserId,
  }) async {
    try {
      final profileResponse = await supabase
          .from('user_profiles')
          .select(
        'account_disable, disabled_by_admin, account_disabled_by_role, last_changed_by',
      )
          .eq('custom_user_id', customUserId)
          .maybeSingle();

      if (profileResponse == null ||
          profileResponse['account_disable'] != true) {
        return null;
      }

      final disabledByAdmin =
          profileResponse['disabled_by_admin'] as bool? ?? false;
      final lastChangedBy = profileResponse['last_changed_by'] as String?;
      final disabledByRole =
      profileResponse['account_disabled_by_role'] as String?;
      if (disabledByAdmin &&
          lastChangedBy != null &&
          lastChangedBy != customUserId) {

        final disablerProfile = await supabase
            .from('user_profiles')
            .select(
          'custom_user_id, name, role, email, mobile_number',
        )
            .eq('custom_user_id', lastChangedBy)
            .maybeSingle();

        final disablerRole =
            disablerProfile?['role'] ?? disabledByRole ?? 'admin';

        final roleLower = disablerRole.toString().toLowerCase();
        final hasAuthority = [
          'admin',
          'agent',
          'truckowner',
          'truck_owner',
          'company',
        ].contains(roleLower);

        if (hasAuthority) {
          return {
            'is_self_disabled': false,
            'disabled_by': lastChangedBy,
            'disabler_name': disablerProfile?['name'] ?? 'Administrator',
            'disabler_role': disablerRole,
            'disabler_email': disablerProfile?['email'],
            'disabler_phone': disablerProfile?['mobile_number'],
            'reason': 'Account disabled by $disablerRole',
          };
        }
      }
      return {
        'is_self_disabled': true,
        'disabled_by': customUserId,
        'reason': 'Self-disabled account',
      };
    } catch (e) {
      print('Error getting account disable info: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> sendReactivationRequest({
    required String requesterId,
    required String requesterName,
    required String disablerId,
    required String requestMessage,
  }) async {
    try {
      final disablerProfile = await supabase
          .from('user_profiles')
          .select('user_id, name, role')
          .eq('custom_user_id', disablerId)
          .maybeSingle();

      if (disablerProfile == null) {
        return {
          'ok': false,
          'error': 'Could not find the admin/agent who disabled your account',
        };
      }

      await NotificationManager().createNotification(
        userId: disablerProfile['user_id'],
        title: 'Account Reactivation Request',
        message:
        '$requesterName is requesting to reactivate their account. Message: "$requestMessage"',
        type: 'account_reactivation_request',
        sourceType: 'account_management',
        sourceId: requesterId,
      );

      await supabase.from('account_status_logs').insert({
        'target_custom_id': requesterId,
        'performed_by_custom_id': requesterId,
        'action_type': 'reactivation_requested',
        'reason': 'User requested reactivation from disabler',
        'metadata': {
          'request_message': requestMessage,
          'sent_to': disablerId,
          'disabler_name': disablerProfile['name'],
          'timestamp': DateTime.now().toIso8601String(),
        },
        'created_at': DateTime.now().toIso8601String(),
      });

      return {
        'ok': true,
        'message': 'Reactivation request sent successfully',
        'disabler_name': disablerProfile['name'],
        'disabler_role': disablerProfile['role'],
      };
    } catch (e) {
      print('Error sending reactivation request: $e');
      return {
        'ok': false,
        'error': 'Failed to send reactivation request: ${e.toString()}',
      };
    }
  }
  static Future<Map<String, dynamic>> enableAccount({
    required String targetCustomId,
    required String performedByCustomId,
    String? reason,
  }) async {
    try {
      await supabase.from('user_profiles').update({
        'account_disable': false,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('custom_user_id', targetCustomId);

      await supabase.from('account_status_logs').insert({
        'target_custom_id': targetCustomId,
        'performed_by_custom_id': performedByCustomId,
        'action_type': 'account_enabled',
        'reason': reason ?? 'Enabled by admin/agent',
        'metadata': {
          'enabled_method': 'admin_approval',
          'timestamp': DateTime.now().toIso8601String(),
        },
        'created_at': DateTime.now().toIso8601String(),
      });

      final targetProfile = await supabase
          .from('user_profiles')
          .select('user_id, name')
          .eq('custom_user_id', targetCustomId)
          .maybeSingle();

      if (targetProfile != null) {
        await NotificationManager().createNotification(
          userId: targetProfile['user_id'],
          title: 'Account Reactivated',
          message: 'Your account has been reactivated. You can now log in.',
          type: 'account_status',
          sourceType: 'account_management',
          sourceId: performedByCustomId,
        );
      }

      return {'ok': true, 'message': 'Account enabled successfully'};
    } catch (e) {
      print('Error enabling account: $e');
      return {
        'ok': false,
        'error': 'Failed to enable account: ${e.toString()}',
      };
    }
  }

  static Future<bool> hasPendingReactivationRequest({
    required String customUserId,
  }) async {
    try {
      final recentRequest = await supabase
          .from('account_status_logs')
          .select('created_at')
          .eq('target_custom_id', customUserId)
          .eq('action_type', 'reactivation_requested')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (recentRequest == null) return false;

      final requestTime = DateTime.parse(recentRequest['created_at']);
      final now = DateTime.now();

      return now.difference(requestTime).inHours < 24;
    } catch (e) {
      print('Error checking pending request: $e');
      return false;
    }
  }
}