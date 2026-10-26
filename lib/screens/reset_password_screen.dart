import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finora/services/auth_provider.dart';
import 'package:finora/services/theme_provider.dart';
import 'package:finora/utils/theme.dart';
import 'package:finora/widgets/gradient_button.dart';

/// Shown after the user opens the password-reset link from their email.
/// The router pins the user here (see `recoveringPassword` in router.dart)
/// until they save a new password or cancel.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  static const _minLength = 6; // Supabase default minimum

  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showPassword = false;
  bool _loading = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool success = false}) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: success ? AppTheme.success : AppTheme.destructive));

  Future<void> _save() async {
    final pw = _passwordCtrl.text;
    if (pw.length < _minLength) {
      _snack('Password must be at least $_minLength characters');
      return;
    }
    if (pw != _confirmCtrl.text) {
      _snack('Passwords do not match');
      return;
    }
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final error = await auth.updatePassword(pw);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      _snack(error);
    } else {
      _snack('Password updated', success: true);
      // The router redirects away from this screen once recovery is cleared.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 64),
            Text('Set a new password',
                style: TextStyle(color: AppTheme.fg(isDark), fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Choose a password you haven\'t used before. At least $_minLength characters.',
                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 13)),
            const SizedBox(height: 28),
            _input(_passwordCtrl, 'New password', isDark,
                obscure: !_showPassword,
                suffix: IconButton(
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                    icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppTheme.muted(isDark), size: 20))),
            const SizedBox(height: 14),
            _input(_confirmCtrl, 'Confirm new password', isDark, obscure: !_showPassword),
            const SizedBox(height: 28),
            GradientButton(label: 'Update Password', onPressed: _save, loading: _loading),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _loading ? null : () => context.read<AuthProvider>().cancelPasswordRecovery(),
                child: Text('Cancel', style: TextStyle(color: AppTheme.muted(isDark))),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _input(TextEditingController ctrl, String hint, bool isDark, {bool obscure = false, Widget? suffix}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.glass(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Row(children: [
        const SizedBox(width: 16),
        Icon(Icons.lock_outline_rounded, color: AppTheme.muted(isDark), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: ctrl,
            obscureText: obscure,
            style: TextStyle(color: AppTheme.fg(isDark), fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: AppTheme.muted(isDark)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        if (suffix != null) suffix,
      ]),
    );
  }
}
