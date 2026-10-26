import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finora/models/expense.dart';
import 'package:finora/services/auth_provider.dart';
import 'package:finora/services/supabase_service.dart';
import 'package:finora/services/spending_lock_provider.dart';
import 'package:finora/services/theme_provider.dart';
import 'package:finora/utils/theme.dart';
import 'package:finora/utils/finance_utils.dart';
import 'package:finora/widgets/bottom_nav.dart';
import 'package:finora/widgets/glass_card.dart';
import 'package:finora/widgets/spending_lock_dialogs.dart';
import 'package:finora/services/notification_service.dart';
import 'package:finora/services/onboarding_service.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<Expense> _expenses = [];
  BudgetLimits _limits = BudgetLimits();
  bool _showAdd = false;
  String _search = '';

  final _amountCtrl = TextEditingController();
  String _category = 'Food';
  String _mood = 'Neutral';
  String _paymentMode = 'UPI';
  bool _isSubscription = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    final expenses = await SupabaseService.getExpenses(user.id);
    final limits = await SupabaseService.getBudgetLimits(user.id);
    if (!mounted) return;
    setState(() {
      _expenses = expenses;
      if (limits != null) _limits = limits;
    });
  }

// ── Check lock BEFORE adding expense ────────────────────────────────────────
  Future<void> _checkLockAndAdd() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) {
      _showSnack('Your session expired. Please log in again.', error: true);
      return;
    }
    final lockProvider = context.read<SpendingLockProvider>();

    // Load lock state if not loaded
    if (lockProvider.lock == null) {
      await lockProvider.load(user.id, _limits.savingsGoal);
    }
    if (!mounted) return;

    // Strict mode block
    if (lockProvider.isStrictLocked) {
      await showDialog(context: context, builder: (_) => const StrictLockDialog());
      return;
    }

    // Soft lock — show emergency unlock dialog
    if (lockProvider.isLocked) {
      final totalSpent = _expenses.fold(0.0, (s, e) => s + e.amount);
      final amount = double.tryParse(_amountCtrl.text) ?? 0;
      final onboarding = await OnboardingService.getOnboarding(user.id);
      if (!mounted) return;
      final income = onboarding?.monthlyIncome ?? 0.0;

      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => SpendingLockDialog(
          amount: amount,
          savingsGoal: _limits.savingsGoal,
          totalSpent: totalSpent,
          monthlyIncome: income,
          emergencyLeft: lockProvider.emergencyLeft,
          onEmergencyUnlock: (reason) async {
            return await lockProvider.useEmergencyUnlock(user.id);
          },
        ),
      );
      if (result != true || !mounted) return;
    }

    // Proceed with actual add
    await _handleAdd();
  }

  Future<void> _handleAdd() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      _showSnack('Enter a valid amount', error: true);
      return;
    }
    final user = context.read<AuthProvider>().user;
    if (user == null) {
      _showSnack('Your session expired. Please log in again.', error: true);
      return;
    }

    final newExp = Expense(
      id: '',
      date: FinanceUtils.toDateKey(DateTime.now()),
      amount: amount,
      category: _category,
      mood: _mood,
      paymentMode: _paymentMode,
      isSubscription: _isSubscription,
    );

    final saved = await SupabaseService.addExpense(user.id, newExp);
    if (!mounted) return;
    if (saved == null) {
      _showSnack(SupabaseService.lastError ?? 'Failed to add expense', error: true);
      return;
    }

    final updated = [saved, ..._expenses];
    setState(() {
      _expenses = updated;
      _showAdd = false;
      _amountCtrl.clear();
      _category = 'Food';
      _mood = 'Neutral';
      _paymentMode = 'UPI';
      _isSubscription = false;
    });

    // ── Check budget and trigger notifications ────────────────────────────────
    final lockProvider = context.read<SpendingLockProvider>();
    final totalSpent = updated.fold(0.0, (s, e) => s + e.amount);

    if (lockProvider.lock != null) {
      final result = await lockProvider.checkAndWarn(
        user.id,
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
        _showSnack('🔒 Account locked after 3 warnings!', error: true);
      } else {
        _showSnack('Expense added ✅');
      }
      if (lockProvider.error != null) {
        _showSnack(lockProvider.error!, error: true);
        lockProvider.clearError();
      }
    } else {
      _showSnack('Expense added ✅');
    }

    // ── Smart notification check after every expense ───────────────────────
    final onboarding = await OnboardingService.getOnboarding(user.id);
    if (!mounted) return;
    final monthlyIncome = onboarding?.monthlyIncome ?? 0.0;
    await NotificationService().checkAndNotify(
      totalSpent: totalSpent,
      budgetLimit: lockProvider.budgetLimit > 0
          ? lockProvider.budgetLimit
          : _limits.savingsGoal,
      savingsGoal: _limits.savingsGoal,
      monthlyIncome: monthlyIncome,
    );
  }

  Future<void> _handleDelete(String id) async {
    final user = context.read<AuthProvider>().user;
    if (user == null) {
      _showSnack('Your session expired. Please log in again.', error: true);
      return;
    }
    await SupabaseService.deleteExpense(user.id, id);
    if (!mounted) return;
    setState(() => _expenses = _expenses.where((e) => e.id != id).toList());
    _showSnack('Expense deleted');
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.destructive : AppTheme.success,
    ));
  }

  List<Expense> get _filtered {
    return _expenses
        .where((e) =>
            _search.isEmpty ||
            e.category.toLowerCase().contains(_search.toLowerCase()) ||
            e.date.contains(_search))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Expenses',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.fg(isDark))),
                      GestureDetector(
                        onTap: () => setState(() => _showAdd = !_showAdd),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [AppTheme.primary, AppTheme.secondary]),
                            borderRadius: BorderRadius.circular(21),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withOpacity(0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: Icon(
                            _showAdd ? Icons.close_rounded : Icons.add_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Add form
                  if (_showAdd) ...[
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Amount
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.bg(isDark).withOpacity(0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                              controller: _amountCtrl,
                              keyboardType: TextInputType.number,
                              style: TextStyle(color: AppTheme.fg(isDark)),
                              decoration: InputDecoration(
                                hintText: 'Amount (₹)',
                                hintStyle: TextStyle(color: AppTheme.muted(isDark)),
                                border: InputBorder.none,
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text('Category',
                              style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: AppConstants.categories.map((c) {
                              final selected = _category == c;
                              return _Chip(
                                label: '${AppConstants.categoryEmojis[c] ?? ''} $c',
                                selected: selected,
                                onTap: () => setState(() => _category = c),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                          Text('Payment',
                              style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
                          const SizedBox(height: 8),
                          Row(
                            children: AppConstants.paymentModes.map((m) {
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _Chip(
                                    label: m,
                                    selected: _paymentMode == m,
                                    onTap: () => setState(() => _paymentMode = m),
                                    fullWidth: true,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                          Text('Mood',
                              style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
                          const SizedBox(height: 8),
                          Row(
                            children: AppConstants.moods.map((m) {
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: _Chip(
                                    label: m,
                                    selected: _mood == m,
                                    onTap: () => setState(() => _mood = m),
                                    fullWidth: true,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Switch(
                                value: _isSubscription,
                                onChanged: (v) => setState(() => _isSubscription = v),
                                activeColor: AppTheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text('Subscription',
                                  style: TextStyle(color: AppTheme.muted(isDark), fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _AddButton(onPressed: _checkLockAndAdd),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Search
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.glass(isDark),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border(isDark)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 14),
                        Icon(Icons.search_rounded,
                            color: AppTheme.muted(isDark), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setState(() => _search = v),
                            style: TextStyle(color: AppTheme.fg(isDark), fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Search expenses...',
                              hintStyle: TextStyle(color: AppTheme.muted(isDark)),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // List
                  if (_filtered.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text('No expenses yet. Add your first one!',
                            style: TextStyle(color: AppTheme.muted(isDark), fontSize: 13)),
                      ),
                    )
                  else
                    ..._filtered.take(50).map((exp) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ExpenseRow(
                            expense: exp,
                            onDelete: () => _handleDelete(exp.id),
                          ),
                        )),
                ],
              ),
            ),
          ),
          const BottomNav(),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool fullWidth;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary])
              : null,
          color: selected ? null : AppTheme.glass(isDark),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.transparent : AppTheme.border(isDark),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.muted(isDark),
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Add Expense',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final Expense expense;
  final VoidCallback onDelete;

  const _ExpenseRow({required this.expense, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emoji = AppConstants.categoryEmojis[expense.category] ?? '📦';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.glass(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.surface(isDark),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(emoji, style: TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.category,
                    style: TextStyle(
                        color: AppTheme.fg(isDark), fontWeight: FontWeight.w500, fontSize: 14)),
                Text('${expense.date} · ${expense.paymentMode}',
                    style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
              ],
            ),
          ),
          Text('₹${expense.amount.toStringAsFixed(0)}',
              style: TextStyle(
                  color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDelete,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.destructive.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.delete_outline_rounded,
                  color: AppTheme.destructive, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}
