import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:finora/services/auth_provider.dart';
import 'package:finora/screens/login_screen.dart';
import 'package:finora/screens/signup_screen.dart';
import 'package:finora/screens/reset_password_screen.dart';
import 'package:finora/screens/onboarding_screen.dart';
import 'package:finora/screens/dashboard_screen.dart';
import 'package:finora/screens/expenses_screen.dart';
import 'package:finora/screens/calendar_screen.dart';
import 'package:finora/screens/predictions_screen.dart';
import 'package:finora/screens/profile_screen.dart';
import 'package:finora/screens/scan_receipt_screen.dart';
import 'package:finora/screens/ai_assistant_screen.dart';
import 'package:finora/screens/add_expense_screen.dart';
import 'package:finora/models/expense.dart';

GoRouter createRouter(BuildContext context) {
  return GoRouter(
    initialLocation: '/',
    // ── FIXED REDIRECT ──────────────────────────────────────────────────────
    // /onboarding is excluded from auth redirect so new users can reach it
    redirect: (context, state) {
      final auth = context.read<AuthProvider>();
      final isAuth = auth.isAuthenticated;
      final path   = state.uri.path;

      // Opened a password-reset link: keep the user on the new-password
      // screen until they finish or cancel.
      if (auth.recoveringPassword) {
        return path == '/reset-password' ? null : '/reset-password';
      }
      if (path == '/reset-password') return isAuth ? '/dashboard' : '/login';

      // These routes are always accessible without login
      final publicRoutes = ['/', '/login', '/signup', '/onboarding'];

      if (!isAuth && !publicRoutes.contains(path)) {
        // Not logged in and trying to access protected route → go to login
        return '/login';
      }

      if (isAuth) {
        // Wait for the first onboarding-status check to resolve before
        // making any onboarding-related redirect decision, so we don't
        // briefly bounce a returning user while their profile loads.
        final checked = auth.onboardingChecked;

        if (checked && auth.needsOnboarding && path != '/onboarding') {
          // First-time user (fresh signup OR a login where onboarding was
          // never finished) → always land on onboarding first.
          return '/onboarding';
        }
        if (path == '/' || path == '/login' || path == '/signup') {
          // Logged in and on auth pages → go to dashboard (unless the
          // check above already routed them to onboarding).
          if (checked && !auth.needsOnboarding) return '/dashboard';
          if (!checked) return null; // wait for the check, avoid a flash
        }
        if (checked && !auth.needsOnboarding && path == '/onboarding') {
          // Already onboarded but somehow landed on /onboarding → dashboard
          return '/dashboard';
        }
      }

      return null;
    },
    refreshListenable: context.read<AuthProvider>(),
    routes: [
      GoRoute(path: '/',            builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/login',       builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup',      builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/onboarding',  builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/reset-password', builder: (_, __) => const ResetPasswordScreen()),
      GoRoute(path: '/dashboard',   builder: (_, __) => const DashboardScreen()),
      GoRoute(path: '/expenses',    builder: (_, __) => const ExpensesScreen()),
      GoRoute(path: '/calendar',    builder: (_, __) => const CalendarScreen()),
      GoRoute(path: '/predictions', builder: (_, __) => const PredictionsScreen()),
      GoRoute(path: '/profile',     builder: (_, __) => const ProfileScreen()),
      GoRoute(path: '/scan-receipt', builder: (_, __) => const ScanReceiptScreen()),
      GoRoute(path: '/ai-assistant', builder: (_, __) => const AiAssistantScreen()),
      // Optional `extra: Expense` lets the OCR screen hand off a
      // pre-filled draft for review — Add Expense still owns the only
      // real save path either way.
      GoRoute(
        path: '/add-expense',
        builder: (_, state) => AddExpenseScreen(initial: state.extra as Expense?),
      ),
    ],
  );
}
