import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:finora/models/expense.dart';
import 'package:finora/models/spending_lock.dart';
import 'package:finora/models/spending_lock_event.dart';
import 'package:finora/services/auth_provider.dart';
import 'package:finora/services/safe_lock_risk_engine.dart';
import 'package:finora/services/spending_lock_provider.dart';
import 'package:finora/services/supabase_service.dart';
import 'package:finora/services/theme_provider.dart';
import 'package:finora/utils/finance_utils.dart';
import 'package:finora/utils/theme.dart';

/// The SafeLock page. Internals are still `SpendingLockScreen` /
/// `SpendingLockProvider` (unchanged class names, so Dashboard/Profile
/// navigation that already points here keeps working) — "SafeLock" is
/// the user-facing name already used in profile_screen.dart.
class SpendingLockScreen extends StatefulWidget {
  const SpendingLockScreen({super.key});

  @override
  State<SpendingLockScreen> createState() => _SpendingLockScreenState();
}

class _SpendingLockScreenState extends State<SpendingLockScreen> {
  final _limitCtrl = TextEditingController();
  List<Expense> _expenses = [];
  double _savingsGoal = 0;
  bool _loadingContext = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEverything());
  }

  @override
  void dispose() {
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEverything() async {
    final user = context.read<AuthProvider>().user;
    final lockProvider = context.read<SpendingLockProvider>();
    if (user == null) {
      // Shouldn't happen — router.dart only lets authenticated users reach
      // this screen — but if it ever does, show something instead of a
      // spinner that never resolves.
      setState(() => _loadingContext = false);
      _showSnack('You need to be logged in to use SafeLock.', error: true);
      return;
    }

    try {
      final limits = await SupabaseService.getBudgetLimits(user.id);
      _savingsGoal = limits?.savingsGoal ?? 0;

      if (lockProvider.lock == null) {
        await lockProvider.load(user.id, _savingsGoal);
      }
      if (!mounted) return;

      final expenses = await SupabaseService.getExpenses(user.id);
      if (!mounted) return;

      setState(() {
        _expenses = expenses;
        _loadingContext = false;
      });

      context.read<SpendingLockProvider>().refreshAssessment(_expenses);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingContext = false);
      _showSnack('Could not load SafeLock. Pull to refresh or check your Supabase setup.', error: true);
    }

    if (mounted && lockProvider.error != null) {
      _showSnack(lockProvider.error!, error: true);
      lockProvider.clearError();
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.destructive : AppTheme.success,
    ));
  }

  Future<void> _confirmReset(SpendingLockProvider lockProvider, String userId) async {
    final isDark = context.read<ThemeProvider>().isDark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface(isDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reset SafeLock?', style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold)),
        content: Text(
          'This clears your warning count back to 0/3 and unlocks your account if it\'s currently active. This can\'t be undone.',
          style: TextStyle(color: AppTheme.muted(isDark)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: AppTheme.muted(isDark))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.destructive, foregroundColor: Colors.white),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await lockProvider.resetLock(userId);
      if (!mounted) return;
      if (lockProvider.error != null) {
        _showSnack(lockProvider.error!, error: true);
        lockProvider.clearError();
      } else {
        _showSnack('SafeLock has been reset ✅');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final lockProvider = context.watch<SpendingLockProvider>();
    final user = context.read<AuthProvider>().user;
    final lock = lockProvider.lock;
    final assessment = lockProvider.lastAssessment;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      body: SafeArea(
        child: (lockProvider.loading || _loadingContext || lock == null || user == null)
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  _Header(isDark: isDark),
                  const SizedBox(height: 20),
                  if (_expenses.isEmpty)
                    _EmptyState(isDark: isDark).animate().fadeIn(duration: 400.ms)
                  else ...[
                    _StatusCard(isDark: isDark, lock: lock)
                        .animate()
                        .fadeIn(duration: 350.ms)
                        .scale(begin: const Offset(0.97, 0.97), curve: Curves.easeOutCubic),
                    const SizedBox(height: 16),
                    _SafetyRingCard(isDark: isDark, assessment: assessment)
                        .animate()
                        .fadeIn(delay: 80.ms, duration: 350.ms)
                        .slideY(begin: 0.08, end: 0),
                    const SizedBox(height: 16),
                    _WarningCard(isDark: isDark, lock: lock, liveReasons: assessment.reasons)
                        .animate()
                        .fadeIn(delay: 140.ms, duration: 350.ms)
                        .slideY(begin: 0.08, end: 0),
                    if (lock.status == SafeLockStatus.active) ...[
                      const SizedBox(height: 16),
                      _ActivationBanner(isDark: isDark)
                          .animate()
                          .fadeIn(duration: 300.ms)
                          .shake(hz: 2, curve: Curves.easeInOut),
                    ],
                    const SizedBox(height: 16),
                    _TodaySpendingCard(isDark: isDark, expenses: _expenses, budgetLimit: lock.budgetLimit),
                    const SizedBox(height: 16),
                    _AiInsightCard(isDark: isDark, expenses: _expenses, assessment: assessment),
                    const SizedBox(height: 16),
                    _RecentEventsCard(isDark: isDark, events: lockProvider.recentEvents),
                    const SizedBox(height: 16),
                    _ControlsCard(
                      isDark: isDark,
                      enabled: lock.enabled,
                      notificationsEnabled: lockProvider.notificationsEnabled,
                      isLocked: lock.lockStatus,
                      onToggleEnabled: (val) async {
                        await lockProvider.toggleEnabled(user.id, val);
                        if (!mounted) return;
                        if (lockProvider.error != null) {
                          _showSnack(lockProvider.error!, error: true);
                          lockProvider.clearError();
                        } else {
                          _showSnack(val ? 'SafeLock is monitoring again ✅' : 'SafeLock paused');
                        }
                      },
                      onToggleNotifications: (val) => lockProvider.setNotificationsEnabled(user.id, val),
                      onReset: () => _confirmReset(lockProvider, user.id),
                    ),
                    const SizedBox(height: 16),
                    _BudgetLimitCard(
                      isDark: isDark,
                      currentLimit: lockProvider.budgetLimit,
                      ctrl: _limitCtrl,
                      onSave: () async {
                        final val = double.tryParse(_limitCtrl.text);
                        if (val == null || val <= 0) {
                          _showSnack('Enter a valid amount', error: true);
                          return;
                        }
                        await lockProvider.updateBudgetLimit(user.id, val);
                        if (!mounted) return;
                        if (lockProvider.error != null) {
                          _showSnack(lockProvider.error!, error: true);
                          lockProvider.clearError();
                          return;
                        }
                        _limitCtrl.clear();
                        lockProvider.refreshAssessment(_expenses);
                        _showSnack('Budget limit updated ✅');
                      },
                    ),
                    const SizedBox(height: 16),
                    _EmergencyCard(isDark: isDark, emergencyLeft: lockProvider.emergencyLeft),
                    const SizedBox(height: 16),
                    _StrictModeCard(
                      isDark: isDark,
                      enabled: lockProvider.strictMode,
                      onToggle: (val) async {
                        await lockProvider.toggleStrictMode(user.id, val);
                        if (!mounted) return;
                        if (lockProvider.error != null) {
                          _showSnack(lockProvider.error!, error: true);
                          lockProvider.clearError();
                        } else {
                          _showSnack(val ? 'Strict Mode enabled 🔒' : 'Strict Mode disabled');
                        }
                      },
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final bool isDark;
  const _Header({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.fg(isDark)),
        onPressed: () => Navigator.pop(context),
      ),
      Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [AppTheme.primary, AppTheme.teal]),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.shield_rounded, color: Colors.white, size: 22),
      ).animate().scale(duration: 450.ms, curve: Curves.elasticOut),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('SafeLock',
                style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold, fontSize: 20)),
            Text('Your spending safety system',
                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
          ],
        ),
      ),
    ]);
  }
}

// ── Main status card ─────────────────────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  final bool isDark;
  final SpendingLock lock;
  const _StatusCard({required this.isDark, required this.lock});

  @override
  Widget build(BuildContext context) {
    final status = lock.status;
    Color color;
    String explanation;
    switch (status) {
      case SafeLockStatus.active:
        color = AppTheme.destructive;
        explanation = 'SafeLock is now protecting your spending inside Finora after 3 warnings.';
        break;
      case SafeLockStatus.monitoring:
        color = AppTheme.success;
        explanation = 'SafeLock watches your spending patterns and warns you before spending gets risky.';
        break;
      case SafeLockStatus.paused:
        color = AppTheme.muted(isDark);
        explanation = 'SafeLock is turned off. Turn it back on to resume monitoring.';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.16), AppTheme.glass(isDark)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.35), width: 1.5),
        boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: color.withOpacity(0.18), shape: BoxShape.circle),
            child: Icon(
              status == SafeLockStatus.active
                  ? Icons.gpp_bad_rounded
                  : status == SafeLockStatus.paused
                      ? Icons.shield_outlined
                      : Icons.verified_user_rounded,
              color: color,
              size: 30,
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
              duration: 1400.ms, begin: const Offset(1, 1), end: const Offset(1.06, 1.06)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                child: Text(status.label,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)),
              ),
              const SizedBox(height: 6),
              Text('${lock.warningCount} / 3 warnings',
                  style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold, fontSize: 17)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Text(explanation, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12.5, height: 1.5)),
      ]),
    );
  }
}

// ── Safety ring ───────────────────────────────────────────────────────────────
class _SafetyRingCard extends StatelessWidget {
  final bool isDark;
  final SafetyAssessment assessment;
  const _SafetyRingCard({required this.isDark, required this.assessment});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (assessment.level) {
      case SafetyLevel.safe:
        color = AppTheme.success;
        label = 'Safe';
        break;
      case SafetyLevel.caution:
        color = AppTheme.warning;
        label = 'Caution';
        break;
      case SafetyLevel.highRisk:
        color = AppTheme.destructive;
        label = 'High Risk';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Row(children: [
        SizedBox(
          width: 84,
          height: 84,
          child: Stack(alignment: Alignment.center, children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: assessment.score.clamp(0.02, 1.0)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, value, __) => CircularProgressIndicator(
                value: value,
                strokeWidth: 8,
                backgroundColor: color.withOpacity(0.12),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            Icon(Icons.shield_moon_rounded, color: color, size: 26),
          ]),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Spending Safety', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 19)),
            const SizedBox(height: 4),
            Text(
              'Based on your budget, category spending and recent activity.',
              style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11.5, height: 1.4),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Warning card ──────────────────────────────────────────────────────────────
class _WarningCard extends StatelessWidget {
  final bool isDark;
  final SpendingLock lock;
  final List<String> liveReasons;
  const _WarningCard({required this.isDark, required this.lock, required this.liveReasons});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Safety Warnings', style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 12),
        Row(children: List.generate(3, (i) {
          final filled = i < lock.warningCount;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 10,
              decoration: BoxDecoration(
                color: filled ? AppTheme.warning : AppTheme.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(5),
              ),
            ).animate(target: filled ? 1 : 0).scale(
                begin: const Offset(0.3, 1), end: const Offset(1, 1), curve: Curves.easeOutBack),
          );
        })),
        const SizedBox(height: 8),
        Text('${lock.warningCount} / 3 warnings issued', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
        if (liveReasons.isNotEmpty) ...[
          const SizedBox(height: 14),
          Divider(color: AppTheme.border(isDark)),
          const SizedBox(height: 8),
          Text('Current risk factors', style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.w600, fontSize: 12.5)),
          const SizedBox(height: 8),
          ...liveReasons.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.circle, size: 6, color: AppTheme.warning),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12.5))),
                ]),
              )),
        ],
      ]),
    );
  }
}

// ── Activation banner ────────────────────────────────────────────────────────
class _ActivationBanner extends StatelessWidget {
  final bool isDark;
  const _ActivationBanner({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.destructive.withOpacity(0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.destructive.withOpacity(0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.gpp_maybe_rounded, color: AppTheme.destructive),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SafeLock is now ACTIVE', style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 6),
            Text(
              'After 3 safety warnings, SafeLock activates enhanced spending protection inside Finora — new expenses show an extra confirmation step. It never blocks Google Pay, PhonePe, bank apps or UPI, only the flow inside this app.',
              style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12, height: 1.5),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Today's spending ──────────────────────────────────────────────────────────
class _TodaySpendingCard extends StatelessWidget {
  final bool isDark;
  final List<Expense> expenses;
  final double budgetLimit;
  const _TodaySpendingCard({required this.isDark, required this.expenses, required this.budgetLimit});

  @override
  Widget build(BuildContext context) {
    final today = FinanceUtils.toDateKey(DateTime.now());
    final todayExpenses = expenses.where((e) => e.date == today).toList();
    final todaySpend = FinanceUtils.getTodaySpending(expenses);
    final monthlySpend = FinanceUtils.getMonthlySpending(expenses);
    final remaining = budgetLimit > 0 ? (budgetLimit - monthlySpend) : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Today's Spending", style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: _StatBlock(isDark: isDark, label: 'Spent today', value: '₹${todaySpend.toStringAsFixed(0)}'),
          ),
          Expanded(
            child: _StatBlock(isDark: isDark, label: 'Transactions', value: '${todayExpenses.length}'),
          ),
          if (remaining != null)
            Expanded(
              child: _StatBlock(
                isDark: isDark,
                label: 'Budget left',
                value: '₹${remaining.toStringAsFixed(0)}',
                color: remaining < 0 ? AppTheme.destructive : AppTheme.success,
              ),
            ),
        ]),
      ]),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final bool isDark;
  final String label;
  final String value;
  final Color? color;
  const _StatBlock({required this.isDark, required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: TextStyle(color: color ?? AppTheme.fg(isDark), fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
    ]);
  }
}

// ── AI Safety Insight ─────────────────────────────────────────────────────────
class _AiInsightCard extends StatelessWidget {
  final bool isDark;
  final List<Expense> expenses;
  final SafetyAssessment assessment;
  const _AiInsightCard({required this.isDark, required this.expenses, required this.assessment});

  String _insight() {
    if (assessment.reasons.isNotEmpty) return assessment.reasons.first;
    if (expenses.isEmpty) return 'Add a few transactions and SafeLock will start monitoring your spending.';
    return 'Your spending is within your current budget.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppTheme.primary.withOpacity(0.12), AppTheme.teal.withOpacity(0.08)]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary.withOpacity(0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.auto_awesome_rounded, color: AppTheme.primary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI Safety Insight', style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            Text(_insight(), style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12.5, height: 1.4)),
          ]),
        ),
      ]),
    );
  }
}

// ── Recent Safety Events ──────────────────────────────────────────────────────
class _RecentEventsCard extends StatelessWidget {
  final bool isDark;
  final List<SpendingLockEvent> events;
  const _RecentEventsCard({required this.isDark, required this.events});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Recent Safety Events', style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 12),
        if (events.isEmpty)
          Text('No safety events yet.', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12.5))
        else
          ...events.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.history_rounded, size: 16, color: AppTheme.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.reason, style: TextStyle(color: AppTheme.fg(isDark), fontSize: 12.5)),
                      Text(
                        '${_relativeTime(e.createdAt)} · warning ${e.warningCountAtTime}/3',
                        style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11),
                      ),
                    ]),
                  ),
                ]),
              )),
      ]),
    );
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool isDark;
  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Column(children: [
        Container(
          width: 84,
          height: 84,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [AppTheme.primary, AppTheme.teal]),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.shield_rounded, color: Colors.white, size: 40),
        ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
        const SizedBox(height: 20),
        Text('SafeLock is ready', style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 8),
        Text(
          'Add a few transactions and SafeLock will start monitoring your spending.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.muted(isDark), fontSize: 13, height: 1.5),
        ),
      ]),
    );
  }
}

// ── Controls ──────────────────────────────────────────────────────────────────
class _ControlsCard extends StatelessWidget {
  final bool isDark;
  final bool enabled;
  final bool notificationsEnabled;
  final bool isLocked;
  final ValueChanged<bool> onToggleEnabled;
  final ValueChanged<bool> onToggleNotifications;
  final VoidCallback onReset;

  const _ControlsCard({
    required this.isDark,
    required this.enabled,
    required this.notificationsEnabled,
    required this.isLocked,
    required this.onToggleEnabled,
    required this.onToggleNotifications,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SafeLock Controls', style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 12),
        _ControlRow(
          isDark: isDark,
          icon: Icons.shield_rounded,
          label: 'SafeLock monitoring',
          value: enabled,
          onChanged: onToggleEnabled,
        ),
        Divider(color: AppTheme.border(isDark)),
        _ControlRow(
          isDark: isDark,
          icon: Icons.notifications_active_rounded,
          label: 'Warning notifications',
          value: notificationsEnabled,
          onChanged: onToggleNotifications,
        ),
        if (isLocked) ...[
          const SizedBox(height: 8),
          Divider(color: AppTheme.border(isDark)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reset warning count'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.success,
                side: const BorderSide(color: AppTheme.success),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _ControlRow extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ControlRow({
    required this.isDark,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 18, color: AppTheme.muted(isDark)),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(color: AppTheme.fg(isDark), fontSize: 13.5))),
        Switch(value: value, onChanged: onChanged, activeColor: AppTheme.primary),
      ]),
    );
  }
}

// ── Budget Limit Card (kept from the previous design) ────────────────────────
class _BudgetLimitCard extends StatelessWidget {
  final bool isDark;
  final double currentLimit;
  final TextEditingController ctrl;
  final VoidCallback onSave;
  const _BudgetLimitCard({required this.isDark, required this.currentLimit, required this.ctrl, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Monthly Budget Limit', style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 4),
        Text('Current: ₹${currentLimit.toStringAsFixed(0)}',
            style: TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: AppTheme.fg(isDark)),
              decoration: InputDecoration(
                hintText: 'New limit (₹)',
                hintStyle: TextStyle(color: AppTheme.muted(isDark)),
                filled: true,
                fillColor: AppTheme.card(isDark),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border(isDark))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border(isDark))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                prefixText: '₹ ',
                prefixStyle: TextStyle(color: AppTheme.fg(isDark)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: onSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            child: const Text('Save'),
          ),
        ]),
      ]),
    );
  }
}

// ── Emergency Card (kept) ─────────────────────────────────────────────────────
class _EmergencyCard extends StatelessWidget {
  final bool isDark;
  final int emergencyLeft;
  const _EmergencyCard({required this.isDark, required this.emergencyLeft});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.bolt_rounded, color: AppTheme.warning, size: 20),
          const SizedBox(width: 8),
          Text('Emergency Unlocks', style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold, fontSize: 15)),
        ]),
        const SizedBox(height: 12),
        Row(children: List.generate(3, (i) {
          final filled = i < emergencyLeft;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 10,
              decoration: BoxDecoration(
                color: filled ? AppTheme.warning : AppTheme.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          );
        })),
        const SizedBox(height: 8),
        Text('$emergencyLeft / 3 emergency unlocks remaining this week', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
      ]),
    );
  }
}

// ── Strict Mode Card (kept) ───────────────────────────────────────────────────
class _StrictModeCard extends StatelessWidget {
  final bool isDark;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  const _StrictModeCard({required this.isDark, required this.enabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: enabled ? AppTheme.destructive.withOpacity(0.08) : AppTheme.surface(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: enabled ? AppTheme.destructive.withOpacity(0.4) : AppTheme.border(isDark)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Strict Mode', style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text('Blocks ALL expenses for 24h after 3 warnings.\nOnly emergency entries allowed.',
                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12, height: 1.5)),
          ]),
        ),
        Switch(value: enabled, onChanged: onToggle, activeColor: AppTheme.destructive),
      ]),
    );
  }
}
