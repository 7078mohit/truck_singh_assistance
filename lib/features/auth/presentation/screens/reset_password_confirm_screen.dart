import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../utils/password_validator.dart';
import '../../utils/auth_exception_handler.dart';

class ResetPasswordPageDeepLink extends StatefulWidget {
  final Uri? uri;
  const ResetPasswordPageDeepLink({super.key, this.uri});

  @override
  State<ResetPasswordPageDeepLink> createState() =>
      _ResetPasswordPageDeepLinkState();
}

class _ResetPasswordPageDeepLinkState extends State<ResetPasswordPageDeepLink> {
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String label, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.grey.shade100,
      prefixIcon: Icon(
        Icons.lock_outline,
        color: Theme.of(context).primaryColorDark,
      ),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
      ),
    );
  }

  void _showDialog(String title, String message, {bool goLogin = false}) {
    showDialog(
      barrierDismissible: !goLogin,
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title.tr()),
        content: Text(message.tr()),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (goLogin) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                      (_) => false,
                );
              }
            },
            child: Text(goLogin ? "go_to_login".tr() : "ok".tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordCtrl.text.trim()),
      );

      if (mounted) {
        _showDialog("success", "password_updated", goLogin: true);
      }
    } on AuthException catch (e) {
      if (mounted) {
        _showDialog("error", AuthExceptionHandler.getErrorMessage(e));
      }
    } catch (_) {
      if (mounted) {
        _showDialog("error", "unexpected_error");
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("set_new_password".tr()),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColorLight,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(20),
            color: Theme.of(context).cardColor,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_person,
                      size: 60,
                      color: Colors.deepPurple,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "create_new_password".tr(),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      enabled: !_loading,
                      decoration: _inputDecoration(
                        "new_password".tr(),
                        suffix: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                            color: Colors.grey.shade600,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: PasswordValidator.validatePassword,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordCtrl,
                      obscureText: _obscure,
                      enabled: !_loading,
                      decoration: _inputDecoration("confirm_new_password".tr()),
                      validator: (value) => value == _passwordCtrl.text
                          ? null
                          : "passwords_do_not_match".tr(),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),

                    const SizedBox(height: 24),

                    // BUTTON
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : _updatePassword,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                            : Text(
                          "update_password".tr(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}