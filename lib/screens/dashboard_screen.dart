import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:finora/models/expense.dart';
import 'package:finora/models/profile.dart';
import 'package:finora/models/onboarding_record.dart';
import 'package:finora/services/auth_provider.dart';
import 'package:finora/services/supabase_service.dart';
import 'package:finora/services/profile_service.dart';
import 'package:finora/services/onboarding_service.dart';
import 'package:finora/services/spending_lock_provider.dart';
import 'package:finora/services/persona_dataset_provider.dart';
import 'package:finora/services/ai_insights_service.dart';
import 'package:finora/utils/theme.dart';
import 'package:finora/utils/finance_utils.dart';
import 'package:finora/widgets/bottom_nav.dart';
import 'package:finora/widgets/glass_card.dart';
import 'dart:async';
import 'package:finora/services/theme_provider.dart';
import 'package:finora/screens/spending_lock_screen.dart';
import 'package:finora/widgets/notification_permission_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Profile? _profile;
  OnboardingRecord? _onboarding;
  List<Expense> _expenses = [];
  BudgetLimits _limits = BudgetLimits();
  DateTime _time = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _time = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    debugPrint('Dashboard: started');
    debugPrint('🟢 Dashboard Started');

    final user = context.read<AuthProvider>().user;
    if (user == null) {
      // No signed-in user to load a dashboard for. This used to be a
      // silent `return` — nothing ever set _profile/_onboarding, so the
      // loader spun forever with no error. Route back to login instead of
      // hanging.
      debugPrint('🔴 Dashboard: no authenticated user — aborting load, going to /login');
      if (mounted) context.go('/login');
      return;
    }

    try {
      final profile = await ProfileService.getProfile(user.id);
      debugPrint('Dashboard: profile loaded');
      debugPrint('🟢 Profile Loaded: ${profile != null}');

      final onboarding = await OnboardingService.getOnboarding(user.id);
      debugPrint('Dashboard: onboarding loaded');
      debugPrint(
        '🟢 Onboarding Loaded: ${onboarding != null}'
        '${onboarding != null ? ' (completed: ${onboarding.onboardingCompleted})' : ''}',
      );

      if (!mounted) return;

      if (profile == null || onboarding == null || !onboarding.onboardingCompleted) {
        // Genuinely incomplete onboarding (not a parsing failure — those
        // are caught below) — send the user to finish it instead of
        // leaving the dashboard spinning.
        debugPrint('🟡 Dashboard: profile/onboarding missing or incomplete — going to /onboarding');
        context.go('/onboarding');
        return;
      }

      setState(() {
        _profile = profile;
        _onboarding = onboarding;
      });

      // Step 2–4: read the persona saved during onboarding and fetch every
      // matching row from persona_dataset, kept in memory for later analysis.
      final persona = onboarding.persona;
      if (persona != null && persona.isNotEmpty) {
        try {
          await context.read<PersonaDatasetProvider>().loadForPersona(persona);
          debugPrint('Dashboard: persona loaded');
          debugPrint('🟢 Persona Loaded: $persona');
        } catch (e) {
          // Non-critical — the dashboard doesn't require persona_dataset
          // rows to render, so don't let this block the rest of the load.
          debugPrint('🔴 Persona load failed (non-fatal): $e');
        }
      } else {
        debugPrint('🟡 Persona Loaded: no persona on this onboarding record');
      }

      List<Expense> expenses = const [];
      try {
        expenses = await SupabaseService.getExpenses(user.id);
        debugPrint('Dashboard: transactions loaded');
        debugPrint('🟢 Dataset Loaded: ${expenses.length} expenses');
      } catch (e) {
        debugPrint('🔴 getExpenses failed (non-fatal, defaulting to empty): $e');
      }
      if (!mounted) return;
      setState(() => _expenses = expenses);

      try {
        final limits = await SupabaseService.getBudgetLimits(user.id);
        debugPrint('🟢 Budget Limits Loaded: ${limits != null}');
        if (!mounted) return;
        if (limits != null) setState(() => _limits = limits);

        // Load spending lock state
        final lockProvider = context.read<SpendingLockProvider>();
        final budgetLimit = limits?.savingsGoal ?? 0;
        await lockProvider.load(user.id, budgetLimit);
      } catch (e) {
        // Spending lock / budget limits are supplementary — a failure here
        // must not leave the (already-rendered) dashboard stuck, since
        // this previously had no try/catch at all and could throw an
        // unhandled exception straight out of an un-awaited initState call.
        debugPrint('🔴 Budget limits / spending lock load failed (non-fatal): $e');
      }

      debugPrint('Dashboard: dashboard ready');
      debugPrint('✅ Dashboard Ready');
    } catch (e, st) {
      // Last-resort net: any unexpected failure anywhere above must not
      // leave the screen on the spinner forever with no explanation.
      debugPrint('🔴 Dashboard _loadData failed: $e\n$st');
    }
  }

  String get _greeting {
    final h = _time.hour;
    if (h < 12) return 'Morning';
    if (h < 17) return 'Afternoon';
    return 'Evening';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_profile == null || _onboarding == null) {
      return Scaffold(
        backgroundColor: AppTheme.bg(isDark),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    final profile = _profile!;
    final onboarding = _onboarding!;

    // ── Derived data (all from real onboarding/expense/budget data — see
    // AiInsightsService for the placeholder AI heuristics used where a
    // dedicated ML model doesn't exist yet). ─────────────────────────────
    final monthlySpent = FinanceUtils.getMonthlySpending(_expenses);
    final datasetCount = context.watch<PersonaDatasetProvider>().dataset.length;

    final monthlyBudget = AiInsightsService.effectiveMonthlyBudget(
      savingsGoal: _limits.savingsGoal,
      monthlyIncome: onboarding.monthlyIncome,
    );
    var predictedSpend = FinanceUtils.predictMonthlySpending(_expenses);
    if (predictedSpend <= 0) predictedSpend = monthlySpent; // not enough history yet

    final confidence = AiInsightsService.personaConfidence(
      onboarding: onboarding,
      datasetRowCount: datasetCount,
    );
    final healthScore = AiInsightsService.healthScore(
      monthlyBudget: monthlyBudget,
      predictedSpend: predictedSpend,
    );
    final budgetWarning = AiInsightsService.budgetWarning(
      predictedSpend: predictedSpend,
      monthlyBudget: monthlyBudget,
    );
    final aiInsight = AiInsightsService.primaryInsight(_expenses, onboarding);
    final personaLabel = (onboarding.persona ?? '').isNotEmpty
        ? onboarding.persona!
        : 'Building your profile';

    final lock = context.watch<SpendingLockProvider>();

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                children: [
                  // Notification permission card (shows only if disabled)
                  const NotificationPermissionCard(),

                  // ── 1. Top header ──────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Good $_greeting, ${profile.fullName} 👋',
                                style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.fg(isDark)),
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Text('🧠 ', style: TextStyle(fontSize: 12)),
                                Flexible(
                                  child: Text(personaLabel,
                                      style: TextStyle(
                                          color: AppTheme.secondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text('AI Confidence: $confidence%',
                                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        children: [
                          _HealthScoreRing(score: healthScore, isDark: isDark),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Consumer<ThemeProvider>(
                                builder: (ctx, tp, _) => _IconChip(
                                  icon: tp.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                                  color: tp.isDark ? AppTheme.warning : AppTheme.primary,
                                  onTap: tp.toggle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              _IconChip(
                                icon: Icons.shield_rounded,
                                color: AppTheme.primary,
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => const SpendingLockScreen())),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.teal]),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Center(
                                  child: Text(
                                    profile.fullName.isNotEmpty ? profile.fullName[0].toUpperCase() : '?',
                                    style: const TextStyle(
                                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── 2. Persona card ────────────────────────────────────
                  GlassCard(
                    borderColor: AppTheme.secondary.withOpacity(0.35),
                    glow: true,
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppTheme.secondary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                              child: Text('🧠', style: TextStyle(fontSize: 20))),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('AI Financial Persona',
                                  style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
                              const SizedBox(height: 2),
                              Text(personaLabel,
                                  style: TextStyle(
                                      color: AppTheme.fg(isDark),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text('AI Confidence: $confidence%',
                                  style: TextStyle(color: AppTheme.secondary, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── 3. AI Budget Prediction card ───────────────────────
                  GlassCard(
                    borderColor: AppTheme.primary.withOpacity(0.35),
                    glow: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('🤖 ', style: TextStyle(fontSize: 15)),
                            Text('AI Budget Prediction',
                                style: TextStyle(
                                    color: AppTheme.fg(isDark),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _BudgetStat(
                                label: 'Monthly Budget',
                                value: '₹${monthlyBudget.toStringAsFixed(0)}',
                                color: AppTheme.fg(isDark),
                                isDark: isDark,
                              ),
                            ),
                            Expanded(
                              child: _BudgetStat(
                                label: 'Spent',
                                value: '₹${monthlySpent.toStringAsFixed(0)}',
                                color: AppTheme.secondary,
                                isDark: isDark,
                              ),
                            ),
                            Expanded(
                              child: _BudgetStat(
                                label: 'Predicted EOM',
                                value: '₹${predictedSpend.toStringAsFixed(0)}',
                                color: predictedSpend > monthlyBudget && monthlyBudget > 0
                                    ? AppTheme.warning
                                    : AppTheme.success,
                                isDark: isDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _PredictionBar(
                          spent: monthlySpent,
                          predicted: predictedSpend,
                          budget: monthlyBudget,
                          isDark: isDark,
                        ),
                        if (budgetWarning != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.warning.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text('⚠️ AI Warning\n$budgetWarning',
                                      style: TextStyle(color: AppTheme.fg(isDark), fontSize: 11.5)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── 4. Quick actions ───────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _QuickAction(
                          emoji: '➕',
                          label: 'Add Expense',
                          isDark: isDark,
                          onTap: () async {
                            final saved = await context.push<bool>('/add-expense');
                            if (saved == true) _loadData();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickAction(
                          emoji: '📷',
                          label: 'Scan Receipt',
                          isDark: isDark,
                          onTap: () => context.go('/scan-receipt'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickAction(
                          emoji: '📊',
                          label: 'Analytics',
                          isDark: isDark,
                          onTap: () => context.go('/predictions'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickAction(
                          emoji: '🤖',
                          label: 'AI Assistant',
                          isDark: isDark,
                          onTap: () => context.go('/ai-assistant'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── 5. Today's / this week's spending chart ────────────
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.bar_chart_rounded, color: AppTheme.primary, size: 18),
                            const SizedBox(width: 8),
                            Text('This Week\'s Spending',
                                style: TextStyle(
                                    color: AppTheme.fg(isDark),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 130,
                          child: _WeekSpendingChart(expenses: _expenses, isDark: isDark),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── 6. Recent transactions ─────────────────────────────
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Recent Transactions',
                                style: TextStyle(
                                    color: AppTheme.fg(isDark),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                            GestureDetector(
                              onTap: () => context.go('/expenses'),
                              child: Text('See all',
                                  style: TextStyle(color: AppTheme.primary, fontSize: 11.5)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_expenses.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text('No transactions yet — add your first expense!',
                                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
                          )
                        else
                          ..._expenses.take(5).map((e) => _TransactionRow(expense: e, isDark: isDark)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── 7. AI Insight ───────────────────────────────────────
                  GlassCard(
                    borderColor: AppTheme.warning.withOpacity(0.3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline_rounded, color: AppTheme.warning, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('💡 AI Insight',
                                  style: TextStyle(
                                      color: AppTheme.fg(isDark),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              Text(aiInsight,
                                  style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── 8. SafeLock status ──────────────────────────────────
                  _SafeLockCard(lock: lock, isDark: isDark),
                ],
              ),
            ),
          ),
          // ── 9. Bottom navigation (existing, reused as-is) ──────────────
          const BottomNav(),
        ],
      ),
    );
  }
}

// ── Header health-score ring ─────────────────────────────────────────────

class _HealthScoreRing extends StatelessWidget {
  final int score;
  final bool isDark;
  const _HealthScoreRing({required this.score, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = score >= 70
        ? AppTheme.success
        : score >= 40
            ? AppTheme.warning
            : AppTheme.destructive;
    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 62,
            height: 62,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 5,
              backgroundColor: AppTheme.border(isDark),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$score',
                  style: TextStyle(
                      color: AppTheme.fg(isDark), fontSize: 15, fontWeight: FontWeight.bold)),
              Text('/100', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 8)),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _IconChip({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppTheme.glass(isDark),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppTheme.border(isDark)),
        ),
        child: Icon(icon, color: color, size: 15),
      ),
    );
  }
}

// ── AI Budget Prediction card pieces ─────────────────────────────────────

class _BudgetStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;
  const _BudgetStat({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 10.5)),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(color: color, fontSize: 13.5, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

class _PredictionBar extends StatelessWidget {
  final double spent;
  final double predicted;
  final double budget;
  final bool isDark;
  const _PredictionBar({
    required this.spent,
    required this.predicted,
    required this.budget,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final denom = budget > 0 ? budget : (predicted > 0 ? predicted : 1);
    final spentRatio = (spent / denom).clamp(0.0, 1.0);
    final predictedRatio = (predicted / denom).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          Container(height: 10, color: AppTheme.border(isDark)),
          FractionallySizedBox(
            widthFactor: predictedRatio,
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.secondary.withOpacity(0.5),
                    predicted > budget && budget > 0 ? AppTheme.warning : AppTheme.secondary,
                  ],
                ),
              ),
            ),
          ),
          FractionallySizedBox(
            widthFactor: spentRatio,
            child: Container(
              height: 10,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [AppTheme.primary, AppTheme.teal]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick actions ─────────────────────────────────────────────────────────

class _QuickAction extends StatelessWidget {
  final String emoji;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _QuickAction({
    required this.emoji,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: AppTheme.glass(isDark),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border(isDark)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                    color: AppTheme.fg(isDark), fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Week spending chart ────────────────────────────────────────────────

class _WeekSpendingChart extends StatelessWidget {
  final List<Expense> expenses;
  final bool isDark;
  const _WeekSpendingChart({required this.expenses, required this.isDark});

  static const _labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysSinceSunday = today.weekday % 7; // Dart: Mon=1..Sun=7 → Sun=0
    final sunday = today.subtract(Duration(days: daysSinceSunday));

    final totals = List<double>.filled(7, 0);
    for (final e in expenses) {
      final d = DateTime.tryParse(e.date);
      if (d == null) continue;
      final dateOnly = DateTime(d.year, d.month, d.day);
      final diff = dateOnly.difference(sunday).inDays;
      if (diff >= 0 && diff < 7) {
        totals[diff] += e.amount;
      }
    }

    final maxVal = totals.reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 100.0 : maxVal * 1.3;

    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppTheme.border(isDark), strokeWidth: 0.5),
          drawVerticalLine: false,
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= _labels.length) return const SizedBox();
                final isToday = idx == daysSinceSunday;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_labels[idx],
                      style: TextStyle(
                          color: isToday ? AppTheme.primary : AppTheme.muted(isDark),
                          fontSize: 9,
                          fontWeight: isToday ? FontWeight.w700 : FontWeight.normal)),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(7, (i) {
          final isToday = i == daysSinceSunday;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: totals[i],
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: isToday
                      ? [AppTheme.secondary, AppTheme.primary]
                      : [AppTheme.primary.withOpacity(0.35), AppTheme.secondary.withOpacity(0.35)],
                ),
                width: 18,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
              ),
            ],
          );
        }),
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

// ── Recent transactions row ────────────────────────────────────────────

class _TransactionRow extends StatelessWidget {
  final Expense expense;
  final bool isDark;
  const _TransactionRow({required this.expense, required this.isDark});

  @override
  Widget build(BuildContext context) {
    // The `expenses` table has no merchant-name column, only a category —
    // so the category doubles as the transaction label here, per the
    // existing schema (see lib/models/expense.dart).
    final emoji = AppConstants.categoryEmojis[expense.category] ?? '📦';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 15))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.category,
                    style: TextStyle(
                        color: AppTheme.fg(isDark), fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text(expense.date,
                    style: TextStyle(color: AppTheme.muted(isDark), fontSize: 10.5)),
              ],
            ),
          ),
          Text('₹${expense.amount.toStringAsFixed(0)}',
              style: TextStyle(
                  color: AppTheme.fg(isDark), fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ── SafeLock card ──────────────────────────────────────────────────────

class _SafeLockCard extends StatelessWidget {
  final SpendingLockProvider lock;
  final bool isDark;
  const _SafeLockCard({required this.lock, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isActivated = lock.isLocked || lock.isStrictLocked;
    final color = isActivated
        ? AppTheme.destructive
        : lock.warningCount > 0
            ? AppTheme.warning
            : AppTheme.success;

    return GlassCard(
      borderColor: color.withOpacity(0.35),
      child: Row(
        children: [
          Icon(Icons.lock_rounded, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isActivated ? '🔒 SafeLock Activated' : '🔒 SafeLock',
                    style: TextStyle(
                        color: AppTheme.fg(isDark), fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  isActivated ? 'Status: Activated' : 'Status: Protected',
                  style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11),
                ),
              ],
            ),
          ),
          if (!isActivated)
            Text('Warnings: ${lock.warningCount}/3',
                style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
