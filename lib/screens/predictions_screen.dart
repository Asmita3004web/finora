import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:finora/models/expense.dart';
import 'package:finora/models/onboarding_record.dart';
import 'package:finora/services/auth_provider.dart';
import 'package:finora/services/supabase_service.dart';
import 'package:finora/services/onboarding_service.dart';
import 'package:finora/services/ai_insights_service.dart';
import 'package:finora/services/analytics_insight_service.dart';
import 'package:finora/services/persona_analysis_service.dart';
import 'package:finora/services/spending_lock_service.dart';
import 'package:finora/widgets/persona_analysis_section.dart';
import 'package:finora/utils/theme.dart';
import 'package:finora/utils/finance_utils.dart';
import 'package:finora/widgets/bottom_nav.dart';
import 'package:finora/widgets/glass_card.dart';

/// Selectable analytics period. Purely a client-side filter over the
/// expenses already fetched once in [_PredictionsScreenState._loadData] —
/// changing the range never re-hits Supabase (see section 14 of the
/// design brief: "do not repeatedly fetch the same data").
enum AnalyticsRange { thisMonth, lastMonth, last3Months, thisYear }

class _RangeInfo {
  final DateTime start;
  final DateTime end;
  final String chipLabel;
  final String dateLabel;
  final double monthsCovered;

  _RangeInfo({
    required this.start,
    required this.end,
    required this.chipLabel,
    required this.dateLabel,
    required this.monthsCovered,
  });
}

_RangeInfo _rangeInfo(AnalyticsRange r, DateTime now) {
  final fmt = DateFormat('MMM d');
  DateTime start;
  DateTime end;
  String chip;
  double months;

  switch (r) {
    case AnalyticsRange.thisMonth:
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month + 1, 0);
      chip = 'This Month';
      months = 1;
      break;
    case AnalyticsRange.lastMonth:
      final prev = DateTime(now.year, now.month - 1, 1);
      start = DateTime(prev.year, prev.month, 1);
      end = DateTime(prev.year, prev.month + 1, 0);
      chip = 'Last Month';
      months = 1;
      break;
    case AnalyticsRange.last3Months:
      final s = DateTime(now.year, now.month - 2, 1);
      start = s;
      end = DateTime(now.year, now.month + 1, 0);
      chip = 'Last 3 Months';
      months = 3;
      break;
    case AnalyticsRange.thisYear:
      start = DateTime(now.year, 1, 1);
      end = DateTime(now.year, 12, 31);
      chip = 'This Year';
      months = now.month.toDouble();
      break;
  }

  return _RangeInfo(
    start: start,
    end: end,
    chipLabel: chip,
    dateLabel: '${fmt.format(start)} - ${fmt.format(end)}',
    monthsCovered: months,
  );
}

class PredictionsScreen extends StatefulWidget {
  const PredictionsScreen({super.key});

  @override
  State<PredictionsScreen> createState() => _PredictionsScreenState();
}

class _PredictionsScreenState extends State<PredictionsScreen> {
  final GlobalKey _recommendationsKey = GlobalKey();
  final PeerComparisonService _peerService = DemoPeerComparisonService();

  List<Expense> _expenses = [];
  List<Expense> _incomes = [];
  double? _monthlyBudget; // spending_locks.budget_limit
  OnboardingRecord? _onboarding;
  BudgetLimits _limits = BudgetLimits();
  AnalyticsRange _range = AnalyticsRange.thisMonth;

  bool _loading = true;
  String? _loadError;
  PeerComparisonResult? _peerInsight;

  static const _categoryColors = [
    AppTheme.primary, AppTheme.secondary, AppTheme.accent,
    AppTheme.warning, AppTheme.success, Color(0xFF60A5FA), Color(0xFFF472B6),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    debugPrint('Analytics: started');
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
    List<Expense> incomes = const [];
    double? monthlyBudget;
    bool hadError = false;

    try {
      expenses = await SupabaseService.getExpenses(user.id);
      debugPrint('Analytics: transactions loaded (${expenses.length})');
    } catch (e) {
      debugPrint('Analytics: getExpenses failed: $e');
      hadError = true;
    }

    try {
      onboarding = await OnboardingService.getOnboarding(user.id);
      debugPrint('Analytics: onboarding loaded');
    } catch (e) {
      debugPrint('Analytics: onboarding load failed: $e');
    }

    try {
      final loaded = await SupabaseService.getBudgetLimits(user.id);
      if (loaded != null) limits = loaded;
    } catch (e) {
      debugPrint('Analytics: budget limits load failed (non-fatal): $e');
    }

    try {
      incomes = await SupabaseService.getIncomes(user.id);
    } catch (e) {
      debugPrint('Analytics: incomes load failed (non-fatal): $e');
    }

    try {
      final lock = await SpendingLockService.getLockState(user.id);
      if (lock != null && lock.budgetLimit > 0) monthlyBudget = lock.budgetLimit;
    } catch (e) {
      debugPrint('Analytics: budget (SafeLock) load failed (non-fatal): $e');
    }

    if (!mounted) return;
    setState(() {
      _incomes = incomes;
      _monthlyBudget = monthlyBudget;
      _expenses = expenses;
      _onboarding = onboarding;
      _limits = limits;
      _loading = false;
      _loadError = hadError
          ? 'Some data couldn\'t be loaded. Pull to retry — showing what\'s available.'
          : null;
    });
    debugPrint('Analytics: ready');

    await _loadPeerInsight();
  }

  Future<void> _loadPeerInsight() async {
    if (_expenses.isEmpty) return;
    final cats = FinanceUtils.getCategoryTotals(_expenses);
    if (cats.isEmpty) return;
    final sorted = cats.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.first;
    final total = cats.values.fold(0.0, (a, b) => a + b);
    try {
      final result = await _peerService.compareTopCategory(
        category: top.key,
        userCategoryTotal: top.value,
        userTotalSpend: total,
        persona: _onboarding?.persona,
      );
      if (!mounted) return;
      setState(() => _peerInsight = result);
    } catch (e) {
      debugPrint('Analytics: peer insight failed (non-fatal): $e');
    }
  }

  void _scrollToRecommendations() {
    final ctx = _recommendationsKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    }
  }

  void _showCategoryDetails(String category, List<Expense> categoryExpenses) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final sorted = [...categoryExpenses]
          ..sort((a, b) => b.date.compareTo(a.date));
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: AppTheme.border(isDark)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(category,
                  style: TextStyle(
                      color: AppTheme.fg(isDark), fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('${sorted.length} transaction${sorted.length == 1 ? '' : 's'} in this period',
                  style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11.5)),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: sorted.take(15).length,
                  itemBuilder: (context, i) {
                    final e = sorted[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(e.date,
                                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
                          ),
                          Text('₹${e.amount.toStringAsFixed(0)}',
                              style: TextStyle(
                                  color: AppTheme.fg(isDark),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  },
                ),
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
    final now = DateTime.now();
    final rangeInfo = _rangeInfo(_range, now);

    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.bg(isDark),
        body: Column(
          children: [
            const Expanded(
              child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
            ),
            const BottomNav(),
          ],
        ),
      );
    }

    if (_expenses.isEmpty) {
      return Scaffold(
        backgroundColor: AppTheme.bg(isDark),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: GlassCard(
                    borderColor: AppTheme.primary.withOpacity(0.35),
                    glow: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.insights_rounded, color: AppTheme.primary, size: 44),
                        const SizedBox(height: 14),
                        Text('No transactions yet',
                            style: TextStyle(
                                color: AppTheme.fg(isDark),
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        const SizedBox(height: 6),
                        Text(
                          'Add your first expense to start seeing AI-powered insights.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12.5),
                        ),
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final saved = await context.push<bool>('/add-expense');
                            if (saved == true) _loadData();
                          },
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add Expense'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const BottomNav(),
          ],
        ),
      );
    }

    // ── Filter to the selected period (local, in-memory only) ───────────
    final filtered = _expenses.where((e) {
      final d = DateTime.tryParse(e.date);
      if (d == null) return false;
      return !d.isBefore(rangeInfo.start) && !d.isAfter(rangeInfo.end);
    }).toList();

    final income = (_onboarding?.monthlyIncome ?? 0) * rangeInfo.monthsCovered;
    final expenseTotal = filtered.fold(0.0, (s, e) => s + e.amount);
    final savings = income - expenseTotal;

    final monthlyBudget = AiInsightsService.effectiveMonthlyBudget(
      savingsGoal: _limits.savingsGoal,
      monthlyIncome: _onboarding?.monthlyIncome ?? 0,
    );

    final catTotals = FinanceUtils.getCategoryTotals(filtered);
    final pieData = catTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final monthlySeries = _buildMonthlySeries(_range, now, _expenses, _onboarding);
    final predicted = FinanceUtils.predictMonthlySpending(_expenses);
    final dailyData = FinanceUtils.getDailySpendingData(_expenses);
    final predictedData = FinanceUtils.getPredictedDailyData(_expenses);
    final trendData = _buildTrendSeries(rangeInfo, dailyData, predictedData);

    // Persona-based analysis (pure calculation over the data loaded above).
    final analysis = PersonaAnalysisService.analyze(
      persona: _onboarding?.persona,
      onboarding: _onboarding,
      expenses: _expenses,
      incomes: _incomes,
      budgetLimit: _monthlyBudget,
      savingsGoal: _limits.savingsGoal,
      periodStart: rangeInfo.start,
      periodEnd: rangeInfo.end,
      monthsCovered: rangeInfo.monthsCovered,
    );
    final recommendations = [
      ...analysis.recommendations.map((r) => '💡 $r'),
      ..._buildRecommendations(filtered, catTotals),
    ];

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
                      _ErrorBanner(text: _loadError!, onRetry: _loadData, isDark: isDark),
                      const SizedBox(height: 12),
                    ],

                    // ── 1. Header ──────────────────────────────────────
                    Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded, color: AppTheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text('AI Financial Analytics',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.fg(isDark))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _RangeSelector(
                      selected: _range,
                      dateLabel: rangeInfo.dateLabel,
                      isDark: isDark,
                      onChanged: (r) => setState(() => _range = r),
                    ),
                    const SizedBox(height: 16),

                    // ── 2. Summary cards ─────────────────────────────────
                    _SummaryCards(income: income, expense: expenseTotal, savings: savings, isDark: isDark),
                    const SizedBox(height: 14),

                    // ── 3. AI Insights card ──────────────────────────────
                    _AiInsightCard(
                      insight: _peerInsight,
                      isDark: isDark,
                      onExplore: _scrollToRecommendations,
                    ),
                    const SizedBox(height: 14),

                    // ── 4. Income vs Expense ─────────────────────────────
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('📊 Income vs Expense',
                              style: TextStyle(
                                  color: AppTheme.fg(isDark), fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(
                            'Income is your declared monthly income, scaled to each month shown '
                            '(no per-transaction income data is stored yet).',
                            style: TextStyle(color: AppTheme.muted(isDark), fontSize: 10),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(height: 190, child: _IncomeExpenseChart(series: monthlySeries)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _LegendDot(color: AppTheme.secondary, label: 'Income'),
                              const SizedBox(width: 16),
                              _LegendDot(color: AppTheme.primary, label: 'Expense'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── 5. Expense breakdown ─────────────────────────────
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('🍰 Expense Breakdown',
                              style: TextStyle(
                                  color: AppTheme.fg(isDark), fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 190,
                            child: _CategoryPieChart(
                              data: pieData,
                              colors: _categoryColors,
                              onTapCategory: (cat) => _showCategoryDetails(
                                  cat, filtered.where((e) => e.category == cat).toList()),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: pieData.asMap().entries.map((e) {
                              final total = pieData.fold(0.0, (s, d) => s + d.value);
                              final pct = total > 0 ? (e.value.value / total * 100).round() : 0;
                              return GestureDetector(
                                onTap: () => _showCategoryDetails(e.value.key,
                                    filtered.where((x) => x.category == e.value.key).toList()),
                                child: _LegendDot(
                                  color: _categoryColors[e.key % _categoryColors.length],
                                  label: '${e.value.key} $pct%',
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── 6. Monthly spending trend ────────────────────────
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('📈 Monthly Spending Trend',
                              style: TextStyle(
                                  color: AppTheme.fg(isDark), fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('Trend-based estimate from your recent spending pattern — '
                              'not a connected ML model yet.',
                              style: TextStyle(color: AppTheme.muted(isDark), fontSize: 10)),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 200,
                            child: _TrendChart(data: trendData, dailyBudget: monthlyBudget / 30),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 14,
                            runSpacing: 6,
                            children: [
                              _LegendDot(color: AppTheme.accent, label: 'Actual'),
                              _LegendDot(color: AppTheme.primary, label: 'Predicted'),
                              _LegendDot(color: AppTheme.warning, label: 'Daily Budget'),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Predicted monthly total: ₹${predicted.toStringAsFixed(0)}',
                              style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── 7. Savings trend ──────────────────────────────────
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('💰 Savings Trend',
                              style: TextStyle(
                                  color: AppTheme.fg(isDark), fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 14),
                          SizedBox(height: 170, child: _SavingsTrendChart(series: monthlySeries)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── 8. Category-wise expenses ────────────────────────
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('📂 Category-wise Expenses',
                              style: TextStyle(
                                  color: AppTheme.fg(isDark), fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(
                            'Per-category budgets aren\'t set up yet — showing actual spending only.',
                            style: TextStyle(color: AppTheme.muted(isDark), fontSize: 10),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 180,
                            child: _CategoryBarChart(
                              data: pieData,
                              colors: _categoryColors,
                              onTapCategory: (cat) => _showCategoryDetails(
                                  cat, filtered.where((e) => e.category == cat).toList()),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── 9. Weekly spending heatmap ───────────────────────
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('🔥 Weekly Spending Heatmap',
                              style: TextStyle(
                                  color: AppTheme.fg(isDark), fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('Last 6 weeks',
                              style: TextStyle(color: AppTheme.muted(isDark), fontSize: 10)),
                          const SizedBox(height: 14),
                          _WeeklyHeatmap(expenses: _expenses, isDark: isDark),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── 10. Persona-based analytics ──────────────────────
                    if (PersonaAnalysisService.hasAnalysis(analysis.persona))
                      PersonaAnalysisSection(result: analysis, isDark: isDark)
                    else
                      _PersonaAnalyticsCard(
                        onboarding: _onboarding,
                        income: income,
                        savings: savings,
                        limits: _limits,
                        isDark: isDark,
                      ),
                    const SizedBox(height: 14),

                    // ── 11. AI Recommendations ───────────────────────────
                    Container(
                      key: _recommendationsKey,
                      child: GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.lightbulb_outline_rounded, color: AppTheme.warning, size: 18),
                                const SizedBox(width: 8),
                                Text('AI Recommendations',
                                    style: TextStyle(
                                        color: AppTheme.fg(isDark),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...recommendations.map((r) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(r,
                                      style: TextStyle(color: AppTheme.fg(isDark), fontSize: 12.5)),
                                )),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Bottom navigation (existing, reused as-is) ───────────────────
          const BottomNav(),
        ],
      ),
    );
  }

  /// Builds a trailing monthly series (Income/Expense/Savings) whose
  /// length depends on the selected range, from the already-fetched
  /// full expense list (never a fresh Supabase call).
  List<_MonthPoint> _buildMonthlySeries(
    AnalyticsRange range,
    DateTime now,
    List<Expense> allExpenses,
    OnboardingRecord? onboarding,
  ) {
    int count;
    switch (range) {
      case AnalyticsRange.thisMonth:
      case AnalyticsRange.lastMonth:
        count = 4;
        break;
      case AnalyticsRange.last3Months:
        count = 3;
        break;
      case AnalyticsRange.thisYear:
        count = now.month;
        break;
    }
    final anchor = range == AnalyticsRange.lastMonth
        ? DateTime(now.year, now.month - 1, 1)
        : DateTime(now.year, now.month, 1);

    final monthlyTotals = FinanceUtils.getMonthlyTotals(allExpenses);
    final income = onboarding?.monthlyIncome ?? 0;

    final months = <_MonthPoint>[];
    for (int i = count - 1; i >= 0; i--) {
      final m = DateTime(anchor.year, anchor.month - i, 1);
      final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
      final expense = monthlyTotals[key] ?? 0.0;
      months.add(_MonthPoint(
        label: DateFormat('MMM').format(m),
        income: income,
        expense: expense,
      ));
    }
    return months;
  }

  List<Map<String, dynamic>> _buildTrendSeries(
    _RangeInfo rangeInfo,
    List<Map<String, dynamic>> dailyData,
    List<Map<String, dynamic>> predictedData,
  ) {
    final actualMap = {for (final d in dailyData) d['date'] as String: d['amount'] as double};
    final predMap = {for (final d in predictedData) d['date'] as String: d['predicted'] as double};
    final allDates = <String>{...actualMap.keys, ...predMap.keys}.toList()..sort();

    final startKey = FinanceUtils.toDateKey(rangeInfo.start);
    final endKey = FinanceUtils.toDateKey(rangeInfo.end);
    var inRange = allDates.where((d) => d.compareTo(startKey) >= 0 && d.compareTo(endKey) <= 0).toList();
    if (inRange.isEmpty) {
      // Range has no daily history yet (e.g. brand-new period) — fall back
      // to the most recent 30 entries so the chart isn't empty.
      inRange = allDates.skip((allDates.length - 30).clamp(0, allDates.length)).toList();
    }

    return inRange.map((d) {
      return {
        'date': d.length >= 5 ? d.substring(5) : d,
        'actual': actualMap[d] ?? 0.0,
        'predicted': predMap[d] ?? 0.0,
      };
    }).toList();
  }

  List<String> _buildRecommendations(List<Expense> filtered, Map<String, double> catTotals) {
    final tips = <String>[];
    if (catTotals.isEmpty) return ['Log a few more expenses to unlock personalized recommendations.'];

    final sorted = catTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    tips.add('💡 Reduce ${sorted.first.key} Spending — it\'s your top category at '
        '₹${sorted.first.value.toStringAsFixed(0)} this period.');

    // Category trend: this month vs previous month, from the full history.
    final now = DateTime.now();
    final thisMonthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final prevMonth = DateTime(now.year, now.month - 1, 1);
    final prevMonthKey = '${prevMonth.year}-${prevMonth.month.toString().padLeft(2, '0')}';

    final thisMonthCats = <String, double>{};
    final prevMonthCats = <String, double>{};
    for (final e in _expenses) {
      final key = e.date.length >= 7 ? e.date.substring(0, 7) : '';
      if (key == thisMonthKey) {
        thisMonthCats[e.category] = (thisMonthCats[e.category] ?? 0) + e.amount;
      } else if (key == prevMonthKey) {
        prevMonthCats[e.category] = (prevMonthCats[e.category] ?? 0) + e.amount;
      }
    }
    for (final entry in thisMonthCats.entries) {
      final prev = prevMonthCats[entry.key];
      if (prev != null && prev > 0) {
        final change = ((entry.value - prev) / prev) * 100;
        if (change >= 15) {
          tips.add('💡 Your ${entry.key} spending increased ${change.round()}% this month.');
          break; // one trend callout is enough to stay concise
        }
      }
    }

    final onboarding = _onboarding;
    if (onboarding != null && _limits.savingsGoal > 0) {
      final monthlySavings = onboarding.monthlyIncome - FinanceUtils.getMonthlySpending(_expenses);
      final progress = (monthlySavings / _limits.savingsGoal * 100);
      if (progress >= 80) {
        tips.add('💡 You are on track for your savings goal.');
      } else if (progress < 40) {
        tips.add('💡 You\'re behind on your savings goal — consider trimming discretionary spending.');
      }
    }

    return tips;
  }
}

class _MonthPoint {
  final String label;
  final double income;
  final double expense;
  const _MonthPoint({required this.label, required this.income, required this.expense});
}

// ── Header / range selector ──────────────────────────────────────────────

class _RangeSelector extends StatelessWidget {
  final AnalyticsRange selected;
  final String dateLabel;
  final bool isDark;
  final ValueChanged<AnalyticsRange> onChanged;

  const _RangeSelector({
    required this.selected,
    required this.dateLabel,
    required this.isDark,
    required this.onChanged,
  });

  static const _options = [
    (AnalyticsRange.thisMonth, 'This Month'),
    (AnalyticsRange.lastMonth, 'Last Month'),
    (AnalyticsRange.last3Months, 'Last 3 Months'),
    (AnalyticsRange.thisYear, 'This Year'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _options.map((opt) {
              final isSelected = opt.$1 == selected;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => onChanged(opt.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primary.withOpacity(0.18) : AppTheme.glass(isDark),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: isSelected ? AppTheme.primary : AppTheme.border(isDark)),
                    ),
                    child: Text(opt.$2,
                        style: TextStyle(
                            color: isSelected ? AppTheme.primary : AppTheme.muted(isDark),
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Text(dateLabel, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11.5)),
      ],
    );
  }
}

// ── Summary cards ──────────────────────────────────────────────────────

class _SummaryCards extends StatelessWidget {
  final double income;
  final double expense;
  final double savings;
  final bool isDark;
  const _SummaryCards({
    required this.income,
    required this.expense,
    required this.savings,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            label: 'Income',
            value: income,
            color: AppTheme.secondary,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryTile(
            label: 'Expense',
            value: expense,
            color: AppTheme.accent,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryTile(
            label: 'Savings',
            value: savings,
            color: savings >= 0 ? AppTheme.success : AppTheme.destructive,
            isDark: isDark,
          ),
        ),
      ],
    );
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
          Text(label, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
          const SizedBox(height: 4),
          Text('₹${value.toStringAsFixed(0)}',
              style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ── AI Insight card ─────────────────────────────────────────────────────

class _AiInsightCard extends StatelessWidget {
  final PeerComparisonResult? insight;
  final bool isDark;
  final VoidCallback onExplore;
  const _AiInsightCard({required this.insight, required this.isDark, required this.onExplore});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderColor: AppTheme.primary.withOpacity(0.4),
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: AppTheme.primary, size: 18),
              const SizedBox(width: 6),
              Text('AI INSIGHTS',
                  style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5)),
              if (insight?.isDemo == true) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.muted(isDark).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('DEMO',
                      style: TextStyle(color: AppTheme.muted(isDark), fontSize: 9, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            insight?.summary ??
                'Add a few more expenses across categories and I\'ll be able to '
                    'compare your spending patterns.',
            style: TextStyle(color: AppTheme.fg(isDark), fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onExplore,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Explore Recommendations',
                    style: TextStyle(color: AppTheme.secondary, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, color: AppTheme.secondary, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error banner ────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String text;
  final VoidCallback onRetry;
  final bool isDark;
  const _ErrorBanner({required this.text, required this.onRetry, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderColor: AppTheme.warning.withOpacity(0.4),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: AppTheme.warning, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: AppTheme.fg(isDark), fontSize: 12)),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ── Charts ───────────────────────────────────────────────────────────────

class _IncomeExpenseChart extends StatelessWidget {
  final List<_MonthPoint> series;
  const _IncomeExpenseChart({required this.series});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (series.isEmpty) return const SizedBox();
    final maxVal = series
        .map((m) => m.income > m.expense ? m.income : m.expense)
        .fold(0.0, (a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 100.0 : maxVal * 1.25;

    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.border(isDark), strokeWidth: 0.5),
          drawVerticalLine: false,
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (v, _) => Text('₹${v.toInt()}',
                  style: TextStyle(color: AppTheme.muted(isDark), fontSize: 9)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= series.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(series[idx].label,
                      style: TextStyle(color: AppTheme.muted(isDark), fontSize: 9)),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: series.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: e.value.income,
                color: AppTheme.secondary,
                width: 9,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4), topRight: Radius.circular(4)),
              ),
              BarChartRodData(
                toY: e.value.expense,
                color: AppTheme.primary,
                width: 9,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4), topRight: Radius.circular(4)),
              ),
            ],
            barsSpace: 4,
          );
        }).toList(),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              '₹${rod.toY.toStringAsFixed(0)}',
              const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}

class _SavingsTrendChart extends StatelessWidget {
  final List<_MonthPoint> series;
  const _SavingsTrendChart({required this.series});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (series.isEmpty) return const SizedBox();
    final spots = series
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.income - e.value.expense))
        .toList();
    final minY = spots.map((s) => s.y).fold(0.0, (a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).fold(0.0, (a, b) => a > b ? a : b);

    return LineChart(
      LineChartData(
        minY: minY < 0 ? minY * 1.2 : 0,
        maxY: maxY <= 0 ? 100 : maxY * 1.2,
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.border(isDark), strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (v, _) => Text('₹${v.toInt()}',
                  style: TextStyle(color: AppTheme.muted(isDark), fontSize: 9)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= series.length) return const SizedBox();
                return Text(series[idx].label,
                    style: TextStyle(color: AppTheme.muted(isDark), fontSize: 9));
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: AppTheme.success,
            barWidth: 2.5,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: AppTheme.success.withOpacity(0.14)),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '₹${s.y.toStringAsFixed(0)}',
                      const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final double dailyBudget;
  const _TrendChart({required this.data, required this.dailyBudget});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (data.isEmpty) return const SizedBox();
    final actualSpots =
        data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value['actual'] as double)).toList();
    final predSpots =
        data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value['predicted'] as double)).toList();
    final budgetSpots =
        data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), dailyBudget)).toList();

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.border(isDark), strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, _) => Text('₹${v.toInt()}',
                  style: TextStyle(color: AppTheme.muted(isDark), fontSize: 9)),
            ),
          ),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: actualSpots,
            color: AppTheme.accent,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: AppTheme.accent.withOpacity(0.10)),
          ),
          LineChartBarData(
            spots: predSpots,
            color: AppTheme.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: budgetSpots,
            color: AppTheme.warning,
            barWidth: 1.5,
            dashArray: [6, 4],
            dotData: const FlDotData(show: false),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '₹${s.y.toStringAsFixed(0)}',
                      TextStyle(color: s.bar.color, fontSize: 11, fontWeight: FontWeight.bold),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _CategoryPieChart extends StatelessWidget {
  final List<MapEntry<String, double>> data;
  final List<Color> colors;
  final ValueChanged<String> onTapCategory;
  const _CategoryPieChart({required this.data, required this.colors, required this.onTapCategory});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox();
    final total = data.fold(0.0, (s, d) => s + d.value);
    return PieChart(
      PieChartData(
        sections: data.asMap().entries.map((e) {
          return PieChartSectionData(
            value: e.value.value,
            color: colors[e.key % colors.length],
            title: total > 0 ? '${((e.value.value / total) * 100).toStringAsFixed(0)}%' : '',
            titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            radius: 68,
          );
        }).toList(),
        sectionsSpace: 3,
        centerSpaceRadius: 38,
        pieTouchData: PieTouchData(
          touchCallback: (event, response) {
            if (!event.isInterestedForInteractions || response?.touchedSection == null) return;
            final idx = response!.touchedSection!.touchedSectionIndex;
            if (idx < 0 || idx >= data.length) return;
            onTapCategory(data[idx].key);
          },
        ),
      ),
    );
  }
}

class _CategoryBarChart extends StatelessWidget {
  final List<MapEntry<String, double>> data;
  final List<Color> colors;
  final ValueChanged<String> onTapCategory;
  const _CategoryBarChart({required this.data, required this.colors, required this.onTapCategory});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (data.isEmpty) return const SizedBox();
    final top = data.take(6).toList();
    final maxVal = top.fold(0.0, (a, b) => a > b.value ? a : b.value);

    return BarChart(
      BarChartData(
        maxY: maxVal <= 0 ? 100 : maxVal * 1.25,
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.border(isDark), strokeWidth: 0.5),
          drawVerticalLine: false,
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (v, _) => Text('₹${v.toInt()}',
                  style: TextStyle(color: AppTheme.muted(isDark), fontSize: 9)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= top.length) return const SizedBox();
                final label = top[idx].key;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(label.length > 6 ? '${label.substring(0, 6)}…' : label,
                      style: TextStyle(color: AppTheme.muted(isDark), fontSize: 8.5)),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: top.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: e.value.value,
                gradient: LinearGradient(
                  colors: [colors[e.key % colors.length].withOpacity(0.6), colors[e.key % colors.length]],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
                width: 18,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6), topRight: Radius.circular(6)),
              ),
            ],
          );
        }).toList(),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              '₹${rod.toY.toStringAsFixed(0)}',
              const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          touchCallback: (event, response) {
            if (!event.isInterestedForInteractions || response?.spot == null) return;
            final idx = response!.spot!.touchedBarGroupIndex;
            if (idx < 0 || idx >= top.length) return;
            onTapCategory(top[idx].key);
          },
        ),
      ),
    );
  }
}

// ── Weekly heatmap ─────────────────────────────────────────────────────

class _WeeklyHeatmap extends StatelessWidget {
  final List<Expense> expenses;
  final bool isDark;
  const _WeeklyHeatmap({required this.expenses, required this.isDark});

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _weeks = 6;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Most recent Monday on/before today.
    final daysSinceMonday = today.weekday - 1;
    final thisMonday = today.subtract(Duration(days: daysSinceMonday));
    final firstMonday = thisMonday.subtract(Duration(days: 7 * (_weeks - 1)));

    // grid[week][dayIndex] = total spent that day
    final grid = List.generate(_weeks, (_) => List<double>.filled(7, 0));
    for (final e in expenses) {
      final d = DateTime.tryParse(e.date);
      if (d == null) continue;
      final dateOnly = DateTime(d.year, d.month, d.day);
      if (dateOnly.isBefore(firstMonday) || dateOnly.isAfter(today)) continue;
      final diffDays = dateOnly.difference(firstMonday).inDays;
      final week = diffDays ~/ 7;
      final dayIdx = diffDays % 7;
      if (week >= 0 && week < _weeks) {
        grid[week][dayIdx] += e.amount;
      }
    }

    double maxVal = 0;
    for (final row in grid) {
      for (final v in row) {
        if (v > maxVal) maxVal = v;
      }
    }

    return Column(
      children: List.generate(7, (dayIdx) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(_dayLabels[dayIdx],
                    style: TextStyle(color: AppTheme.muted(isDark), fontSize: 9.5)),
              ),
              ...List.generate(_weeks, (week) {
                final value = grid[week][dayIdx];
                final intensity = maxVal > 0 ? (value / maxVal).clamp(0.0, 1.0) : 0.0;
                final cellDate = firstMonday.add(Duration(days: week * 7 + dayIdx));
                return Expanded(
                  child: GestureDetector(
                    onTap: value > 0
                        ? () => ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    '${DateFormat('MMM d').format(cellDate)}: ₹${value.toStringAsFixed(0)}'),
                                duration: const Duration(seconds: 2),
                              ),
                            )
                        : null,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 22,
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          AppTheme.glass(isDark),
                          AppTheme.primary,
                          0.15 + intensity * 0.85,
                        ),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: AppTheme.border(isDark), width: 0.5),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      }),
    );
  }
}

// ── Persona analytics ───────────────────────────────────────────────────

class _PersonaAnalyticsCard extends StatelessWidget {
  final OnboardingRecord? onboarding;
  final double income;
  final double savings;
  final BudgetLimits limits;
  final bool isDark;
  const _PersonaAnalyticsCard({
    required this.onboarding,
    required this.income,
    required this.savings,
    required this.limits,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final persona = onboarding?.persona;
    final savingsRate = income > 0 ? (savings / income * 100) : null;
    final discipline = limits.savingsGoal > 0
        ? (savings >= 0 ? 'On track' : 'Needs improvement')
        : 'Not set';
    final goalProgress =
        (onboarding?.financialGoal != null && limits.savingsGoal > 0)
            ? (savings / limits.savingsGoal * 100).clamp(0, 100)
            : null;

    return GlassCard(
      borderColor: AppTheme.secondary.withOpacity(0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your Financial Persona',
              style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
          const SizedBox(height: 4),
          Text(persona ?? 'Not set yet',
              style: TextStyle(color: AppTheme.fg(isDark), fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _PersonaMetric(
                  label: 'Savings Rate',
                  value: savingsRate != null ? '${savingsRate.toStringAsFixed(0)}%' : '—',
                  isDark: isDark,
                ),
              ),
              Expanded(
                child: _PersonaMetric(label: 'Budget Discipline', value: discipline, isDark: isDark),
              ),
              Expanded(
                child: _PersonaMetric(
                  label: 'Goal Progress',
                  value: goalProgress != null ? '${goalProgress.toStringAsFixed(0)}%' : 'Not set',
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PersonaMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  const _PersonaMetric({required this.label, required this.value, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 10)),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(color: AppTheme.secondary, fontSize: 13, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

// ── Shared legend dot ───────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
      ],
    );
  }
}
