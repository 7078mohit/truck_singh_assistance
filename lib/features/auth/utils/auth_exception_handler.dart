import 'package:supabase_flutter/supabase_flutter.dart';

class AuthExceptionHandler {
  static String getErrorMessage(AuthException error) {
    const errors = {
      'Invalid login credentials': 'The email or password is incorrect.',
      'User not found': 'No account found with this email.',
      'Email rate limit exceeded': 'Too many requests. Please try again later.',
      'For security purposes, you can only request this once every 60 seconds':
      'Too many requests. Please try again in a minute.',
    };

    return errors[error.message] ?? error.message;
  }
}