class PasswordValidator {
  static String? validatePassword(String? password) {
    if (password == null || password.isEmpty) {
      return 'Password cannot be empty';
    }

    final rules = {
      RegExp(r'^.{8,}$'): 'Password must be at least 8 characters long',
      RegExp(r'[A-Z]'): 'Password must contain an uppercase letter',
      RegExp(r'[a-z]'): 'Password must contain a lowercase letter',
      RegExp(r'[0-9]'): 'Password must contain a number',
      RegExp(r'[!@#$%^&*(),.?":{}|<>]'):
      'Password must contain a special character',
    };

    for (final rule in rules.entries) {
      if (!rule.key.hasMatch(password)) return rule.value;
    }

    return null;
  }
}