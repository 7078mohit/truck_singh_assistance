import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:logistics_toolkit/features/auth/presentation/screens/register_screen.dart';
import 'package:logistics_toolkit/features/auth/presentation/screens/role_selection_page.dart';
import 'package:logistics_toolkit/features/auth/utils/user_role.dart';
import '../../services/supabase_service.dart';
import 'dashboard_router.dart';

class ProfileSetupPage extends StatefulWidget {
  final UserRole selectedRole;
  const ProfileSetupPage({super.key, required this.selectedRole});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  DateTime? _dob;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final user = SupabaseService.getCurrentUser();
    if (user?.email != null) _emailCtrl.text = user!.email!;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => RoleSelectionPage())),
        ),
        title: Text('complete_your_profile'.tr()),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _roleInfo(),
              const SizedBox(height: 24),
              _textField(_nameCtrl, 'full_name'.tr(), Icons.person,
                  validator: (v) => v!.trim().isEmpty
                      ? 'please_enter_full_name'.tr()
                      : null),
              const SizedBox(height: 16),
              _dobPicker(),
              const SizedBox(height: 16),
              _mobileField(),
              const SizedBox(height: 16),
              _emailField(),
              const SizedBox(height: 32),
              _submitBtn(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleInfo() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.blue.withOpacity(.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(widget.selectedRole.icon, color: Colors.blue),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            "selected_role".tr(
                namedArgs: {"role": widget.selectedRole.displayName}),
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.blue),
          ),
        ),
      ],
    ),
  );

  Widget _textField(TextEditingController c, String label, IconData icon,
      {String? Function(String?)? validator, bool enabled = true}) =>
      TextFormField(
        controller: c,
        validator: validator,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(),
        ),
      );

  Widget _dobPicker() => InkWell(
    onTap: _pickDate,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: 'date_of_birth'.tr(),
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.calendar_today),
      ),
      child: Text(
        _dob == null
            ? 'select_dob'.tr()
            : "${_dob!.day}/${_dob!.month}/${_dob!.year}",
      ),
    ),
  );

  Widget _mobileField() => TextFormField(
    controller: _mobileCtrl,
    keyboardType: TextInputType.phone,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(10)
    ],
    validator: (v) => v == null || v.isEmpty
        ? 'please_enter_mobile'.tr()
        : v.length != 10
        ? 'please_enter_valid_mobile'.tr()
        : null,
    decoration: InputDecoration(
      labelText: 'mobile_number'.tr(),
      prefixText: '+91 ',
      prefixIcon: Icon(Icons.phone),
      border: OutlineInputBorder(),
    ),
  );

  Widget _emailField() => _textField(
    _emailCtrl,
    'email'.tr(),
    Icons.email,
    validator: (value) {
      if (value == null || value.isEmpty) return 'please_enter_email'.tr();
      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
          .hasMatch(value.trim())) return 'please_enter_valid_email'.tr();
      return null;
    },
  );

  Widget _submitBtn() => SizedBox(
    width: double.infinity,
    height: 50,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8))),
      onPressed: _submit,
      child: Text('complete_setup'.tr(),
          style:
          const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    ),
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      initialDate: DateTime.now().subtract(const Duration(days: 6570)),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) return _error('please_select_dob'.tr());

    final user = SupabaseService.getCurrentUser();
    if (user == null) return _error('please_sign_in_continue'.tr());

    setState(() => _loading = true);

    try {
      final customId = await _generateId();
      final ok = await SupabaseService.saveUserProfile(
        userId: user.id,
        customUserId: customId,
        role: widget.selectedRole,
        name: _nameCtrl.text.trim(),
        dateOfBirth: _dob!.toIso8601String(),
        mobileNumber: _mobileCtrl.text.trim(),
        email: user.email,
      );

      if (!ok) return _error('failed_save_profile'.tr());

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile setup completed!')));

      await Future.delayed(const Duration(milliseconds: 600));

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
            builder: (_) => DashboardRouter(role: widget.selectedRole)),
            (_) => false,
      );
    } catch (e) {
      _error('error_occurred'.tr());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _error(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('error'.tr()),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('ok'.tr()))
        ],
      ),
    );
  }

  Future<String> _generateId() async {
    final prefix = widget.selectedRole.prefix;
    final rand = Random();
    for (var i = 0; i < 10; i++) {
      final id = "$prefix${rand.nextInt(10000).toString().padLeft(4, '0')}";
      final exists = await SupabaseService.client
          .from('user_profiles')
          .select()
          .eq('custom_user_id', id)
          .maybeSingle();
      if (exists == null) return id;
    }
    throw Exception('failed_generate_id');
  }
}