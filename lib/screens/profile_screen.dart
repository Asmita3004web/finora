import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:finora/models/expense.dart';
import 'package:finora/models/profile.dart';
import 'package:finora/models/onboarding_record.dart';
import 'package:finora/models/onboarding_data.dart';
import 'package:finora/services/persona_dataset_provider.dart';
import 'package:finora/services/auth_provider.dart';
import 'package:finora/services/supabase_service.dart';
import 'package:finora/services/profile_service.dart';
import 'package:finora/services/onboarding_service.dart';
import 'package:finora/services/spending_lock_provider.dart';
import 'package:finora/services/theme_provider.dart';
import 'package:finora/services/ai_insights_service.dart';
import 'package:finora/utils/theme.dart';
import 'package:finora/utils/finance_utils.dart';
import 'package:finora/widgets/notification_permission_card.dart';
import 'package:finora/widgets/bottom_nav.dart';
import 'package:finora/widgets/glass_card.dart';
import 'package:finora/screens/spending_lock_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Profile? _profile;
  OnboardingRecord? _onboarding;
  String? _personaOverride; // set right after a successful persona change
  BudgetLimits _limits = BudgetLimits();
  List<Expense> _expenses = [];

  bool _loading = true;
  String? _loadError;
  bool _editLimits = false;

  final _dailyCtrl = TextEditingController();
  final _weeklyCtrl = TextEditingController();
  final _goalCtrl = TextEditingController();
  String _savingsGoalText = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  static const _personaDescriptions = {
    'Consistent Saver': 'Saves steadily and tracks spending closely.',
    'Balanced Planner': 'Balances spending, saving and planning.',
    'Lifestyle Spender': 'Spends more on dining, shopping and experiences.',
    'Irregular Spender': 'Income and spending vary a lot month to month.',
    'Loan & EMI Focused': 'A big part of income goes to loans and EMIs.',
    'Goal-Oriented Saver': 'Saves toward specific goals like a trip or gadget.',
  };

  /// Lets the user pick a different persona after login. Saves it to the
  /// `onboarding` row and reloads the matching persona dataset.
  Future<void> _changePersona() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    final isDark = context.read<ThemeProvider>().isDark;
    final current = _onboarding?.persona;

    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bg(isDark),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Change your persona',
                style: TextStyle(color: AppTheme.fg(isDark), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Your insights and predictions will update to match.',
                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
            const SizedBox(height: 12),
            for (final name in OnboardingData.personaEmojis.keys)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(OnboardingData.personaEmojis[name]!, style: const TextStyle(fontSize: 26)),
                title: Text(name,
                    style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.w600)),
                subtitle: Text(_personaDescriptions[name] ?? '',
                    style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
                trailing: name == current
                    ? const Icon(Icons.check_circle_rounded, color: AppTheme.success)
                    : null,
                onTap: () => Navigator.of(ctx).pop(name),
              ),
          ]),
        ),
      ),
    );
    if (picked == null || picked == current || !mounted) return;

    final err = await OnboardingService.updatePersona(user.id, picked);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err), backgroundColor: AppTheme.destructive));
      return;
    }
    // Show the new persona immediately, then refresh the whole screen.
    setState(() => _personaOverride = picked);
    await _loadData();
    if (!mounted) return;
    try {
      await context.read<PersonaDatasetProvider>().loadForPersona(picked);
    } catch (_) {/* non-critical */}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Persona changed to $picked'), backgroundColor: AppTheme.success));
  }

  @override
  void dispose() {
    _dailyCtrl.dispose();
    _weeklyCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
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

    Profile? profile;
    OnboardingRecord? onboarding;
    BudgetLimits limits = BudgetLimits();
    List<Expense> expenses = const [];
    bool hadError = false;

    try {
      profile = await ProfileService.getProfile(user.id);
    } catch (e) {
      debugPrint('Profile: profile load failed: $e');
      hadError = true;
    }

    try {
      onboarding = await OnboardingService.getOnboarding(user.id);
    } catch (e) {
      debugPrint('Profile: onboarding load failed (non-fatal): $e');
    }

    try {
      final loaded = await SupabaseService.getBudgetLimits(user.id);
      if (loaded != null) limits = loaded;
    } catch (e) {
      debugPrint('Profile: budget limits load failed (non-fatal): $e');
    }

    try {
      expenses = await SupabaseService.getExpenses(user.id);
    } catch (e) {
      debugPrint('Profile: expenses load failed (non-fatal): $e');
    }

    try {
      final lockProvider = context.read<SpendingLockProvider>();
      if (lockProvider.lock == null) {
        await lockProvider.load(user.id, limits.savingsGoal);
      }
    } catch (e) {
      debugPrint('Profile: SafeLock load failed (non-fatal): $e');
    }

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _onboarding = onboarding;
      _limits = limits;
      _expenses = expenses;
      _savingsGoalText = limits.savingsGoal > 0 ? limits.savingsGoal.toStringAsFixed(0) : '';
      _dailyCtrl.text = limits.daily.toStringAsFixed(0);
      _weeklyCtrl.text = limits.weekly.toStringAsFixed(0);
      _goalCtrl.text = _savingsGoalText;
      _loading = false;
      _loadError = hadError ? 'Some data couldn\'t be loaded — pull to retry.' : null;
    });
    debugPrint('Profile: loaded');
  }

  Future<void> _saveLimits() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) {
      _showSnack('Your session expired. Please log in again.', error: true);
      return;
    }
    final newLimits = BudgetLimits(
      daily: double.tryParse(_dailyCtrl.text) ?? _limits.daily,
      weekly: double.tryParse(_weeklyCtrl.text) ?? _limits.weekly,
      savingsGoal: _limits.savingsGoal,
    );
    await SupabaseService.upsertBudgetLimits(user.id, newLimits);
    if (!mounted) return;
    setState(() {
      _limits = newLimits;
      _editLimits = false;
    });
    _showSnack('Budget limits updated ✅');
  }

  Future<void> _saveGoal() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) {
      _showSnack('Your session expired. Please log in again.', error: true);
      return;
    }
    final newLimits = BudgetLimits(
      daily: _limits.daily,
      weekly: _limits.weekly,
      savingsGoal: double.tryParse(_goalCtrl.text) ?? 0,
    );
    await SupabaseService.upsertBudgetLimits(user.id, newLimits);
    if (!mounted) return;
    setState(() {
      _limits = newLimits;
      _savingsGoalText = _goalCtrl.text;
    });
    _showSnack('Savings goal set! 🎯');
  }

  Future<void> _editProfileName() async {
    final ctrl = TextEditingController(text: _profile?.fullName ?? '');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface(isDark),
        title: Text('Edit Profile', style: TextStyle(color: AppTheme.fg(isDark))),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: AppTheme.fg(isDark)),
          decoration: const InputDecoration(labelText: 'Full name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || _profile == null) return;
    final user = context.read<AuthProvider>().user;
    if (user == null) {
      _showSnack('Your session expired. Please log in again.', error: true);
      return;
    }
    final ok = await ProfileService.upsertProfile(
      user.id,
      fullName: newName,
      email: _profile!.email,
      phoneNumber: _profile!.phoneNumber,
      profileImage: _profile!.profileImage,
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _profile = Profile(
            id: _profile!.id,
            fullName: newName,
            email: _profile!.email,
            phoneNumber: _profile!.phoneNumber,
            profileImage: _profile!.profileImage,
          ));
      _showSnack('Profile updated ✅');
    } else {
      _showSnack('Couldn\'t update profile right now', error: true);
    }
  }

  void _openNotificationSettings() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: AppTheme.border(isDark)),
          ),
          child: const SingleChildScrollView(child: NotificationSettingsCard()),
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface(isDark),
        title: Text('Log out?', style: TextStyle(color: AppTheme.fg(isDark))),
        content: Text('You\'ll need to sign in again to access your account.',
            style: TextStyle(color: AppTheme.muted(isDark))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out', style: TextStyle(color: AppTheme.destructive)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _handleLogout();
  }

  Future<void> _handleLogout() async {
    await context.read<AuthProvider>().signOut();
    if (!mounted) return;
    context.go('/');
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

    if (_profile == null) {
      return Scaffold(
        backgroundColor: AppTheme.bg(isDark),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: GlassCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded, color: AppTheme.warning, size: 40),
                        const SizedBox(height: 12),
                        Text('Couldn\'t load your profile',
                            style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        TextButton(onPressed: _loadData, child: const Text('Retry')),
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

    final profile = _profile!;
    final onboarding = _onboarding;
    final monthlyIncome = onboarding?.monthlyIncome ?? 0;
    final isStudent = onboarding?.isStudent ?? false;

    final monthlySpent = FinanceUtils.getMonthlySpending(_expenses);
    var predictedSpend = FinanceUtils.predictMonthlySpending(_expenses);
    if (predictedSpend <= 0) predictedSpend = monthlySpent;
    final monthlyBudget = AiInsightsService.effectiveMonthlyBudget(
      savingsGoal: _limits.savingsGoal,
      monthlyIncome: monthlyIncome,
    );
    final currentSavings = monthlyIncome > 0 ? monthlyIncome - monthlySpent : null;

    // Approximate total savings across the months we have expense history
    // for (income is only known as a flat monthly figure, not per
    // transaction, so this is a reasonable estimate rather than an exact
    // ledger total).
    final monthsOfHistory = FinanceUtils.getMonthlyTotals(_expenses).length;
    final totalExpensesAllTime = _expenses.fold(0.0, (s, e) => s + e.amount);
    final totalSavings = (monthlyIncome > 0 && monthsOfHistory > 0)
        ? (monthlyIncome * monthsOfHistory) - totalExpensesAllTime
        : null;

    final hasEnoughDataForHealthScore =
        onboarding != null && (_expenses.isNotEmpty || monthlyBudget > 0);
    final healthScore = hasEnoughDataForHealthScore
        ? AiInsightsService.healthScore(monthlyBudget: monthlyBudget, predictedSpend: predictedSpend)
        : null;

    final goalAmount = double.tryParse(_savingsGoalText) ?? 0;
    final goalProgress = goalAmount > 0 && currentSavings != null
        ? (currentSavings / goalAmount).clamp(0.0, 1.0)
        : 0.0;

    final lock = context.watch<SpendingLockProvider>();

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
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    Text('Profile',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.fg(isDark))),
                    const SizedBox(height: 16),

                    const NotificationPermissionCard(),

                    // ── User card ─────────────────────────────────────
                    GlassCard(
                      glow: true,
                      borderColor: AppTheme.primary.withOpacity(0.35),
                      child: Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary]),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Center(
                              child: Text(
                                profile.fullName.isNotEmpty ? profile.fullName[0].toUpperCase() : '?',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(profile.fullName,
                                    style: TextStyle(
                                        color: AppTheme.fg(isDark), fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 2),
                                Text(profile.email,
                                    style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary]),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(isStudent ? '🎓 Student' : '💼 Professional',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit Profile',
                            icon: Icon(Icons.edit_rounded, color: AppTheme.muted(isDark), size: 18),
                            onPressed: _editProfileName,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Persona + Health score ────────────────────────
                    GlassCard(
                      borderColor: AppTheme.secondary.withOpacity(0.35),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('FINANCIAL PERSONA',
                                    style: TextStyle(
                                        color: AppTheme.muted(isDark),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4)),
                                const SizedBox(height: 4),
                                Text(_personaOverride ?? onboarding?.persona ?? 'Not set yet',
                                    style: TextStyle(
                                        color: AppTheme.fg(isDark), fontSize: 15, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: onboarding == null ? null : _changePersona,
                            child: const Text('Change',
                                style: TextStyle(color: AppTheme.primary, fontSize: 12)),
                          ),
                          if (healthScore != null)
                            _HealthScoreRing(score: healthScore, isDark: isDark)
                          else
                            SizedBox(
                              width: 110,
                              child: Text(
                                'Financial Health Score will appear once enough data is available.',
                                textAlign: TextAlign.right,
                                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 9.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Statistics ─────────────────────────────────────
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 2.1,
                      children: [
                        _StatCard(
                            label: 'Monthly Income',
                            value: monthlyIncome > 0 ? '₹${monthlyIncome.toStringAsFixed(0)}' : 'Not set',
                            color: AppTheme.secondary,
                            isDark: isDark),
                        _StatCard(
                            label: 'Monthly Budget',
                            value: monthlyBudget > 0 ? '₹${monthlyBudget.toStringAsFixed(0)}' : 'Not set',
                            color: AppTheme.primary,
                            isDark: isDark),
                        _StatCard(
                            label: 'Current Savings',
                            value: currentSavings != null ? '₹${currentSavings.toStringAsFixed(0)}' : '—',
                            color: AppTheme.success,
                            isDark: isDark),
                        _StatCard(
                            label: 'Total Savings',
                            value: totalSavings != null ? '₹${totalSavings.toStringAsFixed(0)}' : '—',
                            color: AppTheme.accent,
                            isDark: isDark),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── Goals ──────────────────────────────────────────
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.track_changes_rounded, color: AppTheme.success, size: 20),
                              const SizedBox(width: 8),
                              Text('Financial Goals',
                                  style: TextStyle(
                                      color: AppTheme.fg(isDark), fontWeight: FontWeight.w600, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (onboarding?.financialGoal == null || onboarding!.financialGoal!.isEmpty)
                            Text('No financial goals added yet.',
                                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12.5))
                          else ...[
                            Text(onboarding.financialGoal!,
                                style: TextStyle(
                                    color: AppTheme.fg(isDark), fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            if (goalAmount > 0) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('${(goalProgress * 100).toStringAsFixed(0)}%',
                                      style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
                                  Text(
                                      '₹${(currentSavings ?? 0).clamp(0, double.infinity).toStringAsFixed(0)} / ₹${goalAmount.toStringAsFixed(0)}',
                                      style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: goalProgress,
                                  backgroundColor: AppTheme.surface(isDark),
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                                  minHeight: 8,
                                ),
                              ),
                            ] else
                              Text('Set a savings target below to track progress.',
                                  style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── SafeLock status ────────────────────────────────
                    _SafeLockStatusCard(lock: lock, isDark: isDark),
                    const SizedBox(height: 12),

                    // ── Budget limits (existing, restyled) ─────────────
                    GlassCard(
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.settings_rounded, color: AppTheme.primary, size: 20),
                                  const SizedBox(width: 8),
                                  Text('Budget Limits',
                                      style: TextStyle(
                                          color: AppTheme.fg(isDark),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                ],
                              ),
                              GestureDetector(
                                onTap: () {
                                  if (_editLimits) {
                                    _saveLimits();
                                  } else {
                                    setState(() => _editLimits = true);
                                  }
                                },
                                child: Text(_editLimits ? 'Save' : 'Edit',
                                    style: TextStyle(
                                        color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _LimitRow(
                              label: 'Daily Limit',
                              value: '₹${_limits.daily.toStringAsFixed(0)}',
                              controller: _dailyCtrl,
                              editing: _editLimits),
                          const SizedBox(height: 10),
                          _LimitRow(
                              label: 'Weekly Limit',
                              value: '₹${_limits.weekly.toStringAsFixed(0)}',
                              controller: _weeklyCtrl,
                              editing: _editLimits),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Savings goal target ─────────────────────────────
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Savings Goal Target',
                              style: TextStyle(
                                  color: AppTheme.fg(isDark), fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppTheme.glass(isDark),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.border(isDark)),
                                  ),
                                  child: TextField(
                                    controller: _goalCtrl,
                                    keyboardType: TextInputType.number,
                                    style: TextStyle(color: AppTheme.fg(isDark), fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: 'Target amount (₹)',
                                      hintStyle: TextStyle(color: AppTheme.muted(isDark)),
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: _saveGoal,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary]),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text('Set',
                                      style: TextStyle(
                                          color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Settings list ────────────────────────────────────
                    Text('Settings', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
                    const SizedBox(height: 8),
                    GlassCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _SettingsRow(
                            icon: Icons.notifications_rounded,
                            label: 'Notification Settings',
                            onTap: _openNotificationSettings,
                          ),
                          _SettingsDivider(isDark: isDark),
                          Consumer<ThemeProvider>(
                            builder: (ctx, tp, _) => _SettingsRow(
                              icon: tp.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                              label: 'Theme',
                              trailing: Switch(
                                value: tp.isDark,
                                onChanged: (_) => tp.toggle(),
                                activeColor: AppTheme.primary,
                              ),
                              onTap: tp.toggle,
                            ),
                          ),
                          _SettingsDivider(isDark: isDark),
                          _SettingsRow(
                            icon: Icons.auto_awesome_rounded,
                            label: 'AI Assistant',
                            onTap: () => context.push('/ai-assistant'),
                          ),
                          _SettingsDivider(isDark: isDark),
                          _SettingsRow(
                            icon: Icons.shield_rounded,
                            label: 'Security (SafeLock)',
                            onTap: () => Navigator.push(
                                context, MaterialPageRoute(builder: (_) => const SpendingLockScreen())),
                          ),
                          _SettingsDivider(isDark: isDark),
                          _SettingsRow(
                            icon: Icons.person_rounded,
                            label: 'Edit Profile',
                            onTap: _editProfileName,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Logout ────────────────────────────────────────
                    GestureDetector(
                      onTap: _confirmLogout,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.glass(isDark),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.border(isDark)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.logout_rounded, color: AppTheme.destructive, size: 18),
                            const SizedBox(width: 8),
                            Text('Logout',
                                style: TextStyle(
                                    color: AppTheme.destructive, fontWeight: FontWeight.w600, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
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
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;
  const _StatCard({required this.label, required this.value, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 10)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _HealthScoreRing extends StatelessWidget {
  final int score;
  final bool isDark;
  const _HealthScoreRing({required this.score, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = score >= 70 ? AppTheme.success : (score >= 40 ? AppTheme.warning : AppTheme.destructive);
    return SizedBox(
      width: 58,
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 58,
            height: 58,
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
              Text('$score', style: TextStyle(color: AppTheme.fg(isDark), fontSize: 14, fontWeight: FontWeight.bold)),
              Text('/100', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 8)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SafeLockStatusCard extends StatelessWidget {
  final SpendingLockProvider lock;
  final bool isDark;
  const _SafeLockStatusCard({required this.lock, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final active = lock.isLocked || lock.isStrictLocked;
    final color = active ? AppTheme.destructive : (lock.warningCount > 0 ? AppTheme.warning : AppTheme.success);
    return GlassCard(
      borderColor: color.withOpacity(0.35),
      child: Row(
        children: [
          Icon(Icons.lock_rounded, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(active ? '🔒 SafeLock Active' : '🔒 SafeLock — Protected',
                style: TextStyle(color: AppTheme.fg(isDark), fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          if (!active)
            Text('Warnings: ${lock.warningCount}/3',
                style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  const _SettingsRow({required this.icon, required this.label, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primary, size: 19),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: TextStyle(color: AppTheme.fg(isDark), fontSize: 13.5)),
            ),
            trailing ?? Icon(Icons.chevron_right_rounded, color: AppTheme.muted(isDark), size: 18),
          ],
        ),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  final bool isDark;
  const _SettingsDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: AppTheme.border(isDark), indent: 16, endIndent: 16);
  }
}

class _LimitRow extends StatelessWidget {
  final String label;
  final String value;
  final TextEditingController controller;
  final bool editing;

  const _LimitRow({
    required this.label,
    required this.value,
    required this.controller,
    required this.editing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
        const SizedBox(height: 4),
        editing
            ? Container(
                decoration: BoxDecoration(
                  color: AppTheme.glass(isDark),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border(isDark)),
                ),
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AppTheme.fg(isDark), fontSize: 13),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              )
            : Text(value,
                style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}
