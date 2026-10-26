import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:finora/models/expense.dart';
import 'package:finora/services/auth_provider.dart';
import 'package:finora/services/notification_service.dart';
import 'package:finora/services/onboarding_service.dart';
import 'package:finora/services/spending_lock_provider.dart';
import 'package:finora/services/supabase_service.dart';
import 'package:finora/utils/finance_utils.dart';
import 'package:finora/utils/theme.dart';
import 'package:finora/widgets/glass_card.dart';
import 'package:finora/widgets/spending_lock_dialogs.dart';

/// Dedicated "Add Expense" screen. Reuses [SupabaseService.addExpense] —
/// the same insertion path the existing Expenses list uses — and the same
/// [SpendingLockProvider] SafeLock flow, so there is exactly one place
/// that ever writes to the `expenses` table.
///
/// Optionally accepts a pre-filled [initial] expense (used by the OCR
/// Receipt Scanner to hand off its extracted/edited values for review).
class AddExpenseScreen extends StatefulWidget {
  final Expense? initial;
  const AddExpenseScreen({super.key, this.initial});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _amountCtrl = TextEditingController();
  late String _category;
  late String _paymentMode;
  late String _mood;
  late bool _isSubscription;
  late DateTime _selectedDate;

  bool _saving = false;
  String? _amountError;
  List<Expense> _cachedExpenses = [];
  double _savingsGoal = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _amountCtrl.text = initial != null && initial.amount > 0
        ? initial.amount.toStringAsFixed(0)
        : '';
    _category = initial?.category ?? 'Food';
    _paymentMode = initial?.paymentMode ?? 'UPI';
    _mood = initial?.mood ?? 'Neutral';
    _isSubscription = initial?.isSubscription ?? false;
    _selectedDate = initial != null
        ? (DateTime.tryParse(initial.date) ?? DateTime.now())
        : DateTime.now();
    _preloadContext();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  /// Loads just enough context (existing expenses + savings goal) to run
  /// the same SafeLock check the Expenses screen runs before saving.
  /// Non-fatal on failure — SafeLock simply won't be checked if this
  /// can't load, rather than blocking the whole screen.
  Future<void> _preloadContext() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    try {
      final expenses = await SupabaseService.getExpenses(user.id);
      final limits = await SupabaseService.getBudgetLimits(user.id);
      if (!mounted) return;
      setState(() {
        _cachedExpenses = expenses;
        _savingsGoal = limits?.savingsGoal ?? 0;
      });
    } catch (e) {
      debugPrint('Expense: preload context failed (non-fatal): $e');
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    if (_saving) return; // prevent duplicate taps

    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _amountError = 'Enter a valid amount');
      return;
    }
    setState(() => _amountError = null);

    final user = context.read<AuthProvider>().user;
    if (user == null) {
      _showSnack('Your session expired. Please log in again.', error: true);
      return;
    }

    setState(() => _saving = true);
    debugPrint('Expense: saving');

    try {
      final proceed = await _passSafeLockCheck(amount);
      if (!proceed) {
        setState(() => _saving = false);
        return;
      }

      // The amount here is a plain double and `_selectedDate` is
      // converted to YYYY-MM-DD via FinanceUtils.toDateKey — never a
      // formatted UI string — so the NUMERIC/DATE columns always get the
      // types Postgres expects.
      final newExpense = Expense(
        id: '',
        date: FinanceUtils.toDateKey(_selectedDate),
        amount: amount,
        category: _category,
        mood: _mood,
        paymentMode: _paymentMode,
        isSubscription: _isSubscription,
      );

      final saved = await SupabaseService.addExpense(user.id, newExpense);
      if (!mounted) return;
      if (saved == null) {
        setState(() => _saving = false);
        _showSnack(SupabaseService.lastError ?? 'Couldn\'t save the expense. Please try again.', error: true);
        return;
      }

      debugPrint('Expense: saved');
      await _postSaveChecks(user.id, saved);
      if (!mounted) return;
      _showSnack('Expense added ✅');
      context.pop(true); // let the caller (Home/Calendar/OCR) know to refresh
    } catch (e) {
      debugPrint('Expense: save failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnack('Something went wrong saving this expense.', error: true);
    }
  }

  /// Same SafeLock flow as the existing Expenses screen — strict lock
  /// blocks outright, a soft lock offers an emergency-unlock dialog.
  /// Returns true if the save should proceed.
  Future<bool> _passSafeLockCheck(double amount) async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return false;
    final lockProvider = context.read<SpendingLockProvider>();

    if (lockProvider.lock == null) {
      await lockProvider.load(user.id, _savingsGoal);
    }
    if (!mounted) return false;

    if (lockProvider.isStrictLocked) {
      await showDialog(context: context, builder: (_) => const StrictLockDialog());
      return false;
    }

    if (lockProvider.isLocked) {
      final totalSpent = _cachedExpenses.fold(0.0, (s, e) => s + e.amount);
      final onboarding = await OnboardingService.getOnboarding(user.id);
      if (!mounted) return false;
      final income = onboarding?.monthlyIncome ?? 0.0;

      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => SpendingLockDialog(
          amount: amount,
          savingsGoal: _savingsGoal,
          totalSpent: totalSpent,
          monthlyIncome: income,
          emergencyLeft: lockProvider.emergencyLeft,
          onEmergencyUnlock: (reason) async {
            return await lockProvider.useEmergencyUnlock(user.id);
          },
        ),
      );
      return result == true;
    }

    return true;
  }

  Future<void> _postSaveChecks(String userId, Expense saved) async {
    final lockProvider = context.read<SpendingLockProvider>();
    final updated = [saved, ..._cachedExpenses];
    final totalSpent = updated.fold(0.0, (s, e) => s + e.amount);

    if (lockProvider.lock != null) {
      final result = await lockProvider.checkAndWarn(
        userId,
        updated,
        latestExpenseId: saved.id,
      );
      if (!mounted) return;
      if (result == WarningResult.warned) {
        await showDialog(
          context: context,
          builder: (_) => SpendingWarningDialog(
            warningCount: lockProvider.warningCount,
            spent: totalSpent,
            limit: lockProvider.budgetLimit,
            reasons: lockProvider.lastAssessment.reasons,
            onContinue: () {},
          ),
        );
      } else if (result == WarningResult.locked) {
        // SpendingLockProvider.checkAndWarn already fires the lock
        // notification itself (and respects the notifications toggle) —
        // no need to call it again here.
        _showSnack('🔒 SafeLock is now ACTIVE after 3 warnings', error: true);
      }
      if (lockProvider.error != null) {
        _showSnack(lockProvider.error!, error: true);
        lockProvider.clearError();
      }
    }

    try {
      final onboarding = await OnboardingService.getOnboarding(userId);
      if (!mounted) return;
      await NotificationService().checkAndNotify(
        totalSpent: totalSpent,
        budgetLimit: lockProvider.budgetLimit > 0 ? lockProvider.budgetLimit : _savingsGoal,
        savingsGoal: _savingsGoal,
        monthlyIncome: onboarding?.monthlyIncome ?? 0.0,
      );
    } catch (e) {
      debugPrint('Expense: post-save notification check failed (non-fatal): $e');
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.destructive : AppTheme.success,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Add Expense',
            style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppTheme.fg(isDark),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            // ── Amount ────────────────────────────────────────────────
            GlassCard(
              borderColor: AppTheme.primary.withOpacity(0.4),
              glow: true,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Amount', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('₹',
                          style: TextStyle(
                              color: AppTheme.primary, fontSize: 32, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(
                              color: AppTheme.fg(isDark), fontSize: 32, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: '0.00',
                            hintStyle: TextStyle(color: AppTheme.muted(isDark), fontSize: 32),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: (_) {
                            if (_amountError != null) setState(() => _amountError = null);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_amountError != null) ...[
                    const SizedBox(height: 6),
                    Text(_amountError!, style: TextStyle(color: AppTheme.destructive, fontSize: 11.5)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Category ──────────────────────────────────────────────
            Text('Category', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppConstants.categories.map((c) {
                final selected = _category == c;
                return GestureDetector(
                  onTap: () => setState(() => _category = c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: selected
                          ? const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary])
                          : null,
                      color: selected ? null : AppTheme.glass(isDark),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: selected ? Colors.transparent : AppTheme.border(isDark)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(AppConstants.categoryEmojis[c] ?? '📦', style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(c,
                            style: TextStyle(
                                color: selected ? Colors.white : AppTheme.fg(isDark),
                                fontSize: 12.5,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── Payment method ────────────────────────────────────────
            Text('Payment Method', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: AppConstants.paymentModes.map((p) {
                final selected = _paymentMode == p;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _paymentMode = p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          gradient: selected
                              ? const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary])
                              : null,
                          color: selected ? null : AppTheme.glass(isDark),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: selected ? Colors.transparent : AppTheme.border(isDark)),
                        ),
                        child: Text(p,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: selected ? Colors.white : AppTheme.fg(isDark),
                                fontSize: 12.5,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── Date ──────────────────────────────────────────────────
            Text('Date', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.glass(isDark),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border(isDark)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_rounded, color: AppTheme.primary, size: 18),
                    const SizedBox(width: 10),
                    Text(DateFormat('dd MMM yyyy').format(_selectedDate),
                        style: TextStyle(color: AppTheme.fg(isDark), fontSize: 14)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: AppTheme.muted(isDark)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Additional details (real schema fields: mood + subscription) ─
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Additional Details',
                      style: TextStyle(
                          color: AppTheme.fg(isDark), fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Free-text merchant/notes aren\'t stored yet — there\'s no '
                    'column for them in the current database.',
                    style: TextStyle(color: AppTheme.muted(isDark), fontSize: 10.5),
                  ),
                  const SizedBox(height: 12),
                  Text('Mood', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: AppConstants.moods.map((m) {
                      final selected = _mood == m;
                      return GestureDetector(
                        onTap: () => setState(() => _mood = m),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected ? AppTheme.primary.withOpacity(0.18) : AppTheme.glass(isDark),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: selected ? AppTheme.primary : AppTheme.border(isDark)),
                          ),
                          child: Text(m,
                              style: TextStyle(
                                  color: selected ? AppTheme.primary : AppTheme.muted(isDark),
                                  fontSize: 11.5)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Switch(
                        value: _isSubscription,
                        onChanged: (v) => setState(() => _isSubscription = v),
                        activeColor: AppTheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text('This is a recurring subscription',
                          style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12.5)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Save button ───────────────────────────────────────────
            GestureDetector(
              onTap: _saving ? null : _save,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.35), blurRadius: 16)],
                ),
                child: _saving
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        ),
                      )
                    : const Text('✓ Save Expense',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
