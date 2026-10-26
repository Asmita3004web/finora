import 'package:flutter/material.dart';

/// Shown instead of the real app when lib/config.dart still has
/// placeholder Supabase credentials. Without this, Supabase.initialize()
/// either throws on an invalid URL (confusing red error screen) or, on
/// some platforms, silently leaves every database call failing — which
/// is exactly what made every button in the app look "dead" with zero
/// explanation. This screen makes the real problem impossible to miss.
class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0B1A),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.settings_suggest_rounded, color: Color(0xFF8B5CF6), size: 56),
                  const SizedBox(height: 20),
                  const Text(
                    'Supabase setup needed',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'This app can\'t connect to a database yet because lib/config.dart still has '
                    'placeholder values.\n\n'
                    'Open lib/config.dart and replace supabaseUrl and supabaseAnonKey with your '
                    'real Supabase project\'s Project URL and Publishable (anon) key — found under '
                    'Settings → API in your Supabase dashboard.\n\n'
                    'Then do a full restart (not hot reload) of the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 14, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
