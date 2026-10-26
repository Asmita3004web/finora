import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:finora/services/auth_provider.dart';
import 'package:finora/services/theme_provider.dart';
import 'package:finora/utils/theme.dart';
import 'package:finora/widgets/gradient_button.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _showPassword  = false;
  bool _loading       = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    final name     = _nameCtrl.text.trim();
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _showSnack('Please fill all fields'); return;
    }
    if (password.length < 6) {
      _showSnack('Password must be at least 6 characters'); return;
    }

    setState(() => _loading = true);

    final error = await context.read<AuthProvider>().signUp(
      email: email, password: password, name: name);

    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) { _showSnack(error); return; }

    // Pass name + email to onboarding as extra data
    context.go('/onboarding', extra: {'name': name, 'email': email});
  }

  void _showSnack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: AppTheme.destructive));

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
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset('assets/images/app_logo.jpeg',
                width: 80, height: 80, fit: BoxFit.cover),
            ),
            const SizedBox(height: 16),
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [AppTheme.primary, AppTheme.teal]).createShader(b),
              child: const Text('Create Account',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            const SizedBox(height: 6),
            Text('Start tracking your finances',
              style: TextStyle(color: AppTheme.muted(isDark))),
            const SizedBox(height: 36),
            _buildInput(_nameCtrl, 'Full Name', Icons.person_outline_rounded, isDark: isDark),
            const SizedBox(height: 14),
            _buildInput(_emailCtrl, 'Email address', Icons.mail_outline_rounded,
              isDark: isDark, keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 14),
            _buildInput(_passwordCtrl, 'Password', Icons.lock_outline_rounded,
              isDark: isDark, obscure: !_showPassword,
              suffix: IconButton(
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: AppTheme.muted(isDark), size: 20))),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Password must be at least 6 characters',
                style: TextStyle(
                  color: AppTheme.muted(isDark).withOpacity(0.6), fontSize: 11))),
            const SizedBox(height: 28),
            GradientButton(label: 'Create Account', onPressed: _handleSignup, loading: _loading),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Already have an account? ',
                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 14)),
              GestureDetector(
                onTap: () => context.go('/login'),
                child: const Text('Sign In',
                  style: TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 14))),
            ]),
            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }

  Widget _buildInput(TextEditingController ctrl, String hint, IconData icon, {
    required bool isDark, bool obscure = false,
    TextInputType? keyboardType, Widget? suffix,
  }) {
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
          controller: ctrl,
          obscureText: obscure,
          keyboardType: keyboardType,
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
