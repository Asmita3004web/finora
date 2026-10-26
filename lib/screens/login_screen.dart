import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:finora/services/auth_provider.dart';
import 'package:finora/services/theme_provider.dart';
import 'package:finora/utils/theme.dart';
import 'package:finora/widgets/gradient_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _showPassword  = false;
  bool _loading       = false;

  @override
  void dispose() { _emailCtrl.dispose(); _passwordCtrl.dispose(); super.dispose(); }

  Future<void> _handleLogin() async {
    if (_emailCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      _showSnack('Please fill all fields'); return;
    }
    setState(() => _loading = true);
    final error = await context.read<AuthProvider>().signIn(
      _emailCtrl.text.trim(), _passwordCtrl.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) _showSnack(error);
  }

  void _showSnack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: AppTheme.destructive));

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> _forgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _ForgotPasswordDialog(initialEmail: _emailCtrl.text.trim()),
    );
    if (email == null || !mounted) return; // cancelled
    if (!_emailPattern.hasMatch(email)) {
      _showSnack('Please enter a valid email address');
      return;
    }
    final error = await context.read<AuthProvider>().sendPasswordReset(email);
    if (!mounted) return;
    if (error != null) {
      _showSnack(error);
      return;
    }
    // Step 2: enter the 6-digit code from the email. No link needed.
    final code = await showDialog<String>(
      context: context,
      builder: (_) => _ResetCodeDialog(email: email),
    );
    if (code == null || !mounted) return;
    final verr = await context.read<AuthProvider>().verifyRecoveryCode(email, code);
    if (!mounted) return;
    if (verr != null) _showSnack(verr);
    // On success the router moves to the "Set a new password" screen.
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(children: [
            const SizedBox(height: 48),
            // Theme toggle
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: context.read<ThemeProvider>().toggle,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.glass(isDark),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border(isDark)),
                  ),
                  child: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    color: isDark ? AppTheme.warning : AppTheme.primary, size: 20),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Logo
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset('assets/images/app_logo.jpeg', width: 80, height: 80, fit: BoxFit.cover),
            ),
            const SizedBox(height: 16),
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [AppTheme.primary, AppTheme.teal]).createShader(b),
              child: const Text('Finora',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            const SizedBox(height: 4),
            Text('Secure AI-Driven Finance',
              style: TextStyle(color: AppTheme.muted(isDark), fontSize: 13)),
            const SizedBox(height: 36),
            _buildInput(_emailCtrl, 'Email address', Icons.mail_outline_rounded,
              isDark: isDark, keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 14),
            _buildInput(_passwordCtrl, 'Password', Icons.lock_outline_rounded,
              isDark: isDark, obscure: !_showPassword,
              suffix: IconButton(
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: AppTheme.muted(isDark), size: 20))),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _loading ? null : _forgotPassword,
                child: const Text('Forgot password?',
                  style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
            const SizedBox(height: 12),
            GradientButton(label: 'Sign In', onPressed: _handleLogin, loading: _loading),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text("Don't have an account? ",
                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 14)),
              GestureDetector(
                onTap: () => context.go('/signup'),
                child: const Text('Sign Up',
                  style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 14))),
            ]),
            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }

  Widget _buildInput(TextEditingController ctrl, String hint, IconData icon, {
    required bool isDark, bool obscure = false,
    TextInputType? keyboardType, Widget? suffix}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.glass(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Row(children: [
        const SizedBox(width: 16),
        Icon(icon, color: AppTheme.muted(isDark), size: 20),
        const SizedBox(width: 12),
        Expanded(child: TextField(
          controller: ctrl, obscureText: obscure, keyboardType: keyboardType,
          style: TextStyle(color: AppTheme.fg(isDark), fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppTheme.muted(isDark)),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 16)),
        )),
        if (suffix != null) suffix,
      ]),
    );
  }
}

/// Asks for the account email. Owns its own controller so it is disposed
/// together with the dialog. Pops the trimmed email, or null if cancelled.
class _ForgotPasswordDialog extends StatefulWidget {
  final String initialEmail;
  const _ForgotPasswordDialog({required this.initialEmail});
  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initialEmail);

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    return AlertDialog(
      backgroundColor: AppTheme.bg(isDark),
      title: Text('Reset password', style: TextStyle(color: AppTheme.fg(isDark))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Enter your account email and we'll email you a 6-digit code to set a new password.",
            style: TextStyle(color: AppTheme.muted(isDark), fontSize: 13)),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: AppTheme.fg(isDark), fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Email address',
              hintStyle: TextStyle(color: AppTheme.muted(isDark)),
              prefixIcon: Icon(Icons.mail_outline_rounded, color: AppTheme.muted(isDark), size: 20),
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: AppTheme.muted(isDark)))),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
          child: const Text('Send code', style: TextStyle(color: AppTheme.primary))),
      ],
    );
  }
}

/// Asks for the 6-digit code emailed to the user. Pops the code, or null.
class _ResetCodeDialog extends StatefulWidget {
  final String email;
  const _ResetCodeDialog({required this.email});
  @override
  State<_ResetCodeDialog> createState() => _ResetCodeDialogState();
}

class _ResetCodeDialogState extends State<_ResetCodeDialog> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    return AlertDialog(
      backgroundColor: AppTheme.bg(isDark),
      title: Text('Enter code', style: TextStyle(color: AppTheme.fg(isDark))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('If an account exists for ${widget.email}, we sent a code to it. Enter it below (check spam too).',
            style: TextStyle(color: AppTheme.muted(isDark), fontSize: 13)),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            style: TextStyle(color: AppTheme.fg(isDark), fontSize: 18, letterSpacing: 4),
            decoration: InputDecoration(
              hintText: 'Code',
              counterText: '',
              hintStyle: TextStyle(color: AppTheme.muted(isDark)),
              prefixIcon: Icon(Icons.pin_outlined, color: AppTheme.muted(isDark), size: 20),
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: AppTheme.muted(isDark)))),
        TextButton(
          onPressed: () {
            final c = _ctrl.text.trim();
            if (c.length >= 6) Navigator.of(context).pop(c);
          },
          child: const Text('Verify', style: TextStyle(color: AppTheme.primary))),
      ],
    );
  }
}
