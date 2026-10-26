import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:finora/models/expense.dart';
import 'package:finora/models/onboarding_record.dart';
import 'package:finora/services/auth_provider.dart';
import 'package:finora/services/onboarding_service.dart';
import 'package:finora/services/supabase_service.dart';
import 'package:finora/services/ai_insights_service.dart';
import 'package:finora/utils/theme.dart';
import 'package:finora/utils/finance_utils.dart';
import 'package:finora/widgets/bottom_nav.dart';
import 'package:finora/widgets/glass_card.dart';

/// "Financial Calendar". Reuses the existing `expenses` data/service —
/// grouped by date locally — plus onboarding/budget data for the summary
/// cards. No new data store, no schema changes.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<Expense> _expenses = [];
  OnboardingRecord? _onboarding;
  BudgetLimits _limits = BudgetLimits();
  DateTime _selectedDate = DateTime.now();
  late DateTime _focusedMonth;

  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _focusedMonth = DateTime(_selectedDate.year, _selectedDate.month);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    final user = context.read<AuthProvider>().user;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    List<Expense> expenses = const [];
    OnboardingRecord? onboarding;
    BudgetLimits limits = BudgetLimits();
    bool hadError = false;

    try {
      expenses = await SupabaseService.getExpenses(user.id);
      debugPrint('Calendar: transactions loaded (${expenses.length})');
    } catch (e) {
      debugPrint('Calendar: getExpenses failed: $e');
      hadError = true;
    }

    try {
      onboarding = await OnboardingService.getOnboarding(user.id);
    } catch (e) {
      debugPrint('Calendar: onboarding load failed (non-fatal): $e');
    }

    try {
      final loaded = await SupabaseService.getBudgetLimits(user.id);
      if (loaded != null) limits = loaded;
    } catch (e) {
      debugPrint('Calendar: budget limits load failed (non-fatal): $e');
    }

    if (!mounted) return;
    setState(() {
      _expenses = expenses;
      _onboarding = onboarding;
      _limits = limits;
      _loading = false;
      _loadError = hadError ? 'Some data couldn\'t be loaded — showing what\'s available.' : null;
    });
  }

  Set<String> get _expenseDates => _expenses.map((e) => e.date).toSet();

  List<Expense> get _dayExpenses {
    final key = FinanceUtils.toDateKey(_selectedDate);
    final list = _expenses.where((e) => e.date == key).toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  double get _monthlyExpense {
    return _expenses.where((e) {
      final d = DateTime.tryParse(e.date);
      return d != null && d.year == _focusedMonth.year && d.month == _focusedMonth.month;
    }).fold(0.0, (s, e) => s + e.amount);
  }

  Future<void> _openAddExpense() async {
    final saved = await context.push<bool>('/add-expense');
    if (saved == true && mounted) _loadData();
  }

  void _showTransactionDetail(Expense e) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: AppTheme.border(isDark)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(AppConstants.categoryEmojis[e.category] ?? '📦',
                      style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Text(e.category,
                      style: TextStyle(
                          color: AppTheme.fg(isDark), fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              _DetailRow(label: 'Amount', value: '₹${e.amount.toStringAsFixed(0)}', isDark: isDark),
              _DetailRow(label: 'Category', value: e.category, isDark: isDark),
              _DetailRow(label: 'Payment Method', value: e.paymentMode, isDark: isDark),
              _DetailRow(label: 'Date', value: e.date, isDark: isDark),
              _DetailRow(label: 'Mood', value: e.mood, isDark: isDark),
              if (e.isSubscription) _DetailRow(label: 'Recurring', value: 'Subscription', isDark: isDark),
              const SizedBox(height: 4),
              Text(
                'Merchant/description aren\'t stored yet — the expenses table '
                'doesn\'t have those columns.',
                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 10),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.bg(isDark),
        body: Column(
          children: [
            const Expanded(child: Center(child: CircularProgressIndicator(color: AppTheme.primary))),
            const BottomNav(),
          ],
        ),
      );
    }

    final dayExpenses = _dayExpenses;
    final monthlyExpense = _monthlyExpense;
    final monthlyIncome = _onboarding?.monthlyIncome ?? 0;
    final monthlyBudget = AiInsightsService.effectiveMonthlyBudget(
      savingsGoal: _limits.savingsGoal,
      monthlyIncome: monthlyIncome,
    );
    final budgetLeft = monthlyBudget - monthlyExpense;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: _loadData,
                color: AppTheme.primary,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  children: [
                    if (_loadError != null) ...[
                      GlassCard(
                        borderColor: AppTheme.warning.withOpacity(0.4),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: AppTheme.warning, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(_loadError!,
                                  style: TextStyle(color: AppTheme.fg(isDark), fontSize: 12)),
                            ),
                            TextButton(onPressed: _loadData, child: const Text('Retry')),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    Row(
                      children: [
                        Icon(Icons.calendar_month_rounded, color: AppTheme.primary, size: 22),
                        const SizedBox(width: 10),
                        Text('Financial Calendar',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.fg(isDark))),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${_monthName(_focusedMonth.month)} ${_focusedMonth.year} · Financial Overview',
                        style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
                    const SizedBox(height: 16),

                    // ── Summary cards ─────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryTile(
                              label: 'Monthly Expense',
                              value: monthlyExpense,
                              color: AppTheme.accent,
                              isDark: isDark),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SummaryTile(
                              label: 'Monthly Income',
                              value: monthlyIncome,
                              color: AppTheme.secondary,
                              isDark: isDark),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SummaryTile(
                              label: 'Budget Left',
                              value: budgetLeft,
                              color: budgetLeft >= 0 ? AppTheme.success : AppTheme.destructive,
                              isDark: isDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // ── Calendar ──────────────────────────────────────
                    GlassCard(
                      child: _CalendarGrid(
                        focusedMonth: _focusedMonth,
                        selectedDate: _selectedDate,
                        expenseDates: _expenseDates,
                        onDateSelected: (d) => setState(() => _selectedDate = d),
                        onMonthChanged: (m) => setState(() => _focusedMonth = m),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Selected day transactions ─────────────────────
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Transactions (${_selectedDate.day} ${_monthName(_selectedDate.month)})',
                              style: TextStyle(
                                  color: AppTheme.fg(isDark), fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 12),
                          if (dayExpenses.isEmpty) ...[
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text('No transactions on this day.',
                                    style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12.5)),
                              ),
                            ),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: _openAddExpense,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                      colors: [AppTheme.primary, AppTheme.secondary]),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text('+ Add Expense',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                              ),
                            ),
                          ] else
                            ...dayExpenses.map((e) => GestureDetector(
                                  onTap: () => _showTransactionDetail(e),
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      children: [
                                        Text('${AppConstants.categoryEmojis[e.category] ?? '📦'} ',
                                            style: const TextStyle(fontSize: 16)),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(e.category,
                                                  style: TextStyle(
                                                      color: AppTheme.fg(isDark), fontSize: 13)),
                                              Text(e.paymentMode,
                                                  style: TextStyle(
                                                      color: AppTheme.muted(isDark), fontSize: 11)),
                                            ],
                                          ),
                                        ),
                                        Text('₹${e.amount.toStringAsFixed(0)}',
                                            style: TextStyle(
                                                color: AppTheme.accent,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13)),
                                        const SizedBox(width: 4),
                                        Icon(Icons.chevron_right_rounded,
                                            color: AppTheme.muted(isDark), size: 18),
                                      ],
                                    ),
                                  ),
                                )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const BottomNav(),
        ],
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool isDark;
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 10.5)),
          const SizedBox(height: 4),
          Text('₹${value.toStringAsFixed(0)}',
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  const _DetailRow({required this.label, required this.value, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
          Text(value,
              style: TextStyle(color: AppTheme.fg(isDark), fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Calendar grid (Mon–Sun) ───────────────────────────────────────────

class _CalendarGrid extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime selectedDate;
  final Set<String> expenseDates;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onMonthChanged;

  const _CalendarGrid({
    required this.focusedMonth,
    required this.selectedDate,
    required this.expenseDates,
    required this.onDateSelected,
    required this.onMonthChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final firstDay = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final daysInMonth = DateTime(focusedMonth.year, focusedMonth.month + 1, 0).day;
    final startWeekday = firstDay.weekday - 1; // Mon=0 .. Sun=6
    final today = DateTime.now();

    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: () => onMonthChanged(DateTime(focusedMonth.year, focusedMonth.month - 1)),
              icon: Icon(Icons.chevron_left_rounded, color: AppTheme.muted(isDark)),
            ),
            Text('${months[focusedMonth.month - 1]} ${focusedMonth.year}',
                style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.w700, fontSize: 15)),
            IconButton(
              onPressed: () => onMonthChanged(DateTime(focusedMonth.year, focusedMonth.month + 1)),
              icon: Icon(Icons.chevron_right_rounded, color: AppTheme.muted(isDark)),
            ),
          ],
        ),
        Row(
          children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) {
            return Expanded(
              child: Center(
                child: Text(d, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 10.5)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.85),
          itemCount: daysInMonth + startWeekday,
          itemBuilder: (_, i) {
            if (i < startWeekday) return const SizedBox();
            final day = i - startWeekday + 1;
            final date = DateTime(focusedMonth.year, focusedMonth.month, day);
            final dateKey = FinanceUtils.toDateKey(date);
            final isSelected = FinanceUtils.toDateKey(selectedDate) == dateKey;
            final isToday = FinanceUtils.toDateKey(today) == dateKey;
            // Only "Expense" transactions exist in this schema (no
            // separate income/goal transaction tables), so the only dot
            // colour ever shown is purple — see spec for the intended
            // cyan/green meanings once those data sources exist.
            final hasExpense = expenseDates.contains(dateKey);

            return GestureDetector(
              onTap: () => onDateSelected(date),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: isSelected
                        ? const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary])
                        : null,
                    color: !isSelected && isToday ? AppTheme.primary.withOpacity(0.12) : null,
                    border: !isSelected
                        ? Border.all(
                            color: isToday ? AppTheme.primary.withOpacity(0.5) : AppTheme.border(isDark),
                            width: isToday ? 1.2 : 0.6)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$day',
                          style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : isToday
                                      ? AppTheme.primary
                                      : AppTheme.fg(isDark),
                              fontSize: 12,
                              fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal)),
                      const SizedBox(height: 2),
                      if (hasExpense)
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? Colors.white : AppTheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
