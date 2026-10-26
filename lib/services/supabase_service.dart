import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:finora/config.dart';
import 'package:finora/models/expense.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  /// Set right before getExpenses/addExpense return null/[] on failure, so
  /// screens can show the real reason instead of a generic "something went
  /// wrong" — without changing every call site's try/catch shape. Cleared
  /// at the start of each call.
  static String? lastError;

  /// Turns a raw exception into a message that's safe and useful to show
  /// directly to the user, instead of a raw PostgrestException dump.
  static String _friendlyError(Object e) {
    final text = e.toString();
    if (text.contains('42P01') ||
        text.contains('PGRST205') ||
        text.contains('Could not find the table') ||
        (text.contains('relation') && text.contains('does not exist'))) {
      return 'Database tables are missing. Run supabase/full_schema.sql in your Supabase SQL editor, then restart the app.';
    }
    if (text.contains('SocketException') || text.contains('Failed host lookup')) {
      return 'Could not reach Supabase. Check your internet connection and that your project is not paused.';
    }
    if (text.contains('401') || text.contains('Invalid API key') || text.contains('JWT')) {
      return 'Supabase rejected the request (invalid URL/key). Double-check lib/config.dart.';
    }
    if (text.contains('row-level security') || text.contains('RLS')) {
      return 'Permission denied by Supabase (row-level security). Make sure you ran the RLS policies in full_schema.sql.';
    }
    return 'Something went wrong talking to the database. Please try again.';
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  static Future<AuthResponse> signIn(String email, String password) =>
      client.auth.signInWithPassword(email: email, password: password);

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
  }) =>
      client.auth.signUp(
        email: email,
        password: password,
        data: {'name': name},
      );

  static Future<void> signOut() => client.auth.signOut();

  /// Emails a password-reset link. The link opens [authRedirectUrl] (deep
  /// link) so the app can show its "set new password" screen.
  static Future<void> sendPasswordReset(String email) =>
      client.auth.resetPasswordForEmail(email, redirectTo: authRedirectUrl);

  /// Verifies the 6-digit code from the reset email (no deep link needed).
  /// On success a recovery session is created and the app can set a new password.
  static Future<AuthResponse> verifyRecoveryCode(String email, String code) =>
      client.auth.verifyOTP(email: email, token: code, type: OtpType.recovery);

  /// Sets a new password for the currently signed-in (recovery) session.
  static Future<UserResponse> updatePassword(String newPassword) =>
      client.auth.updateUser(UserAttributes(password: newPassword));

  static User? get currentUser => client.auth.currentUser;

  static Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  // ── Profile / Onboarding ─────────────────────────────────────────────────
  // Moved out to ProfileService (lib/services/profile_service.dart) and
  // OnboardingService (lib/services/onboarding_service.dart) so each service
  // only ever talks to the one table it owns.

  // ── Expenses ──────────────────────────────────────────────────────────────
  // Backed by the real `transactions` table (there is no `expenses` table —
  // querying one caused PGRST205 "table not found"). Every read/write here
  // filters/sets `transaction_type = 'Expense'` so this app's expense
  // tracking never touches or corrupts Income-type rows that may also live
  // in `transactions`.

  static Future<List<Expense>> getExpenses(String userId) async {
    lastError = null;
    try {
      final data = await client
          .from('transactions')
          .select()
          .eq('user_id', userId)
          .eq('transaction_type', 'Expense')
          .order('transaction_date', ascending: false);
      return (data as List).map((e) => Expense.fromMap(e)).toList();
    } catch (e) {
      debugPrint('getExpenses error: $e');
      lastError = _friendlyError(e);
      return [];
    }
  }

  /// Income rows from `transactions` (`transaction_type = 'Income'`), parsed
  /// with the same shape as expenses (date / amount / category). The app has
  /// no screen that creates income rows yet, so this is normally empty —
  /// callers must fall back to onboarding.monthly_income and say so.
  static Future<List<Expense>> getIncomes(String userId) async {
    try {
      final data = await client
          .from('transactions')
          .select()
          .eq('user_id', userId)
          .eq('transaction_type', 'Income')
          .order('transaction_date', ascending: false);
      return (data as List).map((e) => Expense.fromMap(e)).toList();
    } catch (e) {
      debugPrint('getIncomes error: $e');
      return [];
    }
  }

  static Future<Expense?> addExpense(String userId, Expense expense) async {
    lastError = null;
    try {
      final res = await client
          .from('transactions')
          .insert(expense.toMap(userId))
          .select()
          .single();
      return Expense.fromMap(res);
    } catch (e) {
      debugPrint('addExpense error: $e');
      lastError = _friendlyError(e);
      return null;
    }
  }

  static Future<void> deleteExpense(String userId, String expenseId) async {
    try {
      // Scoped by user_id as well as id — defense in depth alongside RLS,
      // so this can never touch another user's row even if a policy is
      // ever misconfigured.
      await client.from('transactions').delete().eq('id', expenseId).eq('user_id', userId);
    } catch (e) {
      debugPrint('deleteExpense error: $e');
    }
  }

  static Future<void> bulkInsertExpenses(String userId, List<Expense> expenses) async {
    try {
      final rows = expenses.map((e) => e.toMap(userId)).toList();
      await client.from('transactions').insert(rows);
    } catch (e) {
      debugPrint('bulkInsertExpenses error: $e');
    }
  }

  // ── Budget Limits ─────────────────────────────────────────────────────────
  // There is no `budget_limits` table (or any other budget-target table) in
  // the real database — querying one caused PGRST205. Onboarding has no
  // numeric daily/weekly/savings-goal columns either, so there is genuinely
  // no server-side place to store these targets without a schema change,
  // which is out of scope here. Rather than fabricate a table or a fake
  // value, these targets are kept as an honest on-device preference (same
  // approach already used for the AI Assistant's avatar choice) — every
  // caller keeps the same method signature, so no screen needed to change.
  static Future<BudgetLimits?> getBudgetLimits(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('budget_limits_$userId');
      if (raw == null) return null;
      return BudgetLimits.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('getBudgetLimits error: $e');
      return null;
    }
  }

  static Future<void> upsertBudgetLimits(String userId, BudgetLimits limits) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('budget_limits_$userId', jsonEncode(limits.toMap()));
    } catch (e) {
      debugPrint('upsertBudgetLimits error: $e');
    }
  }
}
