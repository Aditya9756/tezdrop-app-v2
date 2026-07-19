import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/app_state_provider.dart';
import '../widgets/initials_avatar.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppStateProvider>().user;
    _nameCtrl  = TextEditingController(text: user?.name ?? '');
    _emailCtrl = TextEditingController(text: user?.email ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Name cannot be empty'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    context.read<AppStateProvider>().updateProfile(
          name : name,
          email: _emailCtrl.text.trim(),
        );
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Profile Updated! ✅'),
      backgroundColor: AppColors.green,
      behavior: SnackBarBehavior.floating,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppStateProvider>().user;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Avatar — live preview, updates as the name field changes
          Center(
            child: InitialsAvatar(
              name: _nameCtrl.text.isEmpty
                  ? (user?.name ?? '?')
                  : _nameCtrl.text,
              radius: 50,
              fontSize: 40,
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('Your avatar is based on your name',
                style: TextStyle(
                    color: AppColors.textGrey, fontSize: 12)),
          ),
          const SizedBox(height: 32),

          // Name field
          _label('Full Name'),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Your full name'),
          ),
          const SizedBox(height: 16),

          // Email field
          _label('Email Address'),
          const SizedBox(height: 6),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'email@example.com'),
          ),
          const SizedBox(height: 16),

          // Phone (disabled)
          _label('Phone (cannot change)'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(user?.phone ?? '',
                style: const TextStyle(
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              child: const Text('Save Changes ✅'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textGrey,
          letterSpacing: 0.5));
}
