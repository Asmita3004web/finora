import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:finora/config.dart';
import 'package:finora/services/auth_provider.dart';
import 'package:finora/services/theme_provider.dart';
import 'package:finora/services/spending_lock_provider.dart';
import 'package:finora/services/persona_dataset_provider.dart';
import 'package:finora/services/notification_service.dart';
import 'package:finora/screens/setup_required_screen.dart';
import 'package:finora/utils/theme.dart';
import 'package:finora/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 0. Bail out early with a clear screen if credentials are still
  // placeholders, instead of every database call failing silently later.
  // See lib/config.dart — that's the only file you need to edit.
  if (!isSupabaseConfigured) {
    runApp(const SetupRequiredScreen());
    return;
  }

  // ── 1. Initialize Supabase ─────────────────────────────────────────────────
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  } catch (e) {
    debugPrint('Supabase.initialize failed: $e');
    runApp(const SetupRequiredScreen());
    return;
  }

  // ── 2. Initialize Notifications ────────────────────────────────────────────
  await NotificationService().initNotifications();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => SpendingLockProvider()),
        ChangeNotifierProvider(create: (_) => PersonaDatasetProvider()),
      ],
      child: const FinoraApp(),
    ),
  );
}

class FinoraApp extends StatefulWidget {
  const FinoraApp({super.key});
  @override
  State<FinoraApp> createState() => _FinoraAppState();
}

class _FinoraAppState extends State<FinoraApp> {
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    _router = createRouter(context);
    _requestNotifPermission();
  }

  Future<void> _requestNotifPermission() async {
    await NotificationService().requestPermission();
    // Schedule daily reminder at 8:00 PM IST
    await NotificationService().scheduleDailyReminder(hour: 20, minute: 0);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp.router(
      title: 'Finora',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeProvider.themeMode,
      debugShowCheckedModeBanner: false,
      routerConfig: _router!,
    );
  }
}
