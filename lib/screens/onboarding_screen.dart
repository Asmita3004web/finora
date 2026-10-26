import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:finora/models/onboarding_data.dart';
import 'package:finora/services/auth_provider.dart';
import 'package:finora/services/profile_service.dart';
import 'package:finora/services/onboarding_service.dart';
import 'package:finora/services/persona_dataset_provider.dart';
import 'package:finora/services/theme_provider.dart';
import 'package:finora/utils/theme.dart';
import 'package:finora/widgets/gradient_button.dart';
import 'package:finora/widgets/onboarding/onboarding_widgets.dart';

/// Total number of pages in the PageView, in order:
/// 0 Welcome · 1 Profession · 2 Income type · 3 Monthly income ·
/// 4 Fixed expenses · 5 Spending habit · 6 Financial goal ·
/// 7 Savings habit · 8 Budget discipline · 9 Expense tracking ·
/// 10 AI assistant · 11 Final / success
const int _kTotalPages = 12;
const int _kFirstQuestionStep = 1;
const int _kLastQuestionStep = 10;

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final _incomeCtrl = TextEditingController();
  final _data = OnboardingData();

  int _currentPage = 0;
  bool _saving = false;
  String _passedName = '';
  String _passedEmail = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra;
    if (extra is Map<String, dynamic>) {
      _passedName = extra['name'] as String? ?? '';
      _passedEmail = extra['email'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _incomeCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.destructive : AppTheme.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _goTo(int page) {
    HapticFeedback.lightImpact();
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _next() async {
    if (!_data.isStepValid(_currentPage)) {
      HapticFeedback.heavyImpact();
      _showSnack(_validationMessage(_currentPage));
      return;
    }
    if (_currentPage == _kTotalPages - 2) {
      // Moving into the final screen -> persist everything now.
      await _saveAndFinish();
      return;
    }
    _goTo(_currentPage + 1);
  }

  void _previous() {
    if (_currentPage == 0) return;
    _goTo(_currentPage - 1);
  }

  void _skip() {
    // Skip just moves past this one (optional) step, without validating it.
    if (_currentPage < _kTotalPages - 2) _goTo(_currentPage + 1);
  }

  String _validationMessage(int step) {
    switch (step) {
      case 1:
        return 'Please select your profession';
      case 2:
        return 'Please select how you earn your income';
      case 3:
        return 'Please enter a valid monthly income';
      case 5:
        return 'Please select your spending habit';
      case 6:
        return 'Please select your biggest financial goal';
      case 7:
        return 'Please select how much you usually save';
      case 8:
        return 'Please tell us how often you exceed your budget';
      case 9:
        return 'Please select how often you track expenses';
      default:
        return 'Please complete this step to continue';
    }
  }

  Future<void> _saveAndFinish() async {
    setState(() => _saving = true);

    String? userId = context.read<AuthProvider>().user?.id;
    String? userEmail = context.read<AuthProvider>().user?.email;
    if (userId == null) {
      final session = Supabase.instance.client.auth.currentSession;
      userId = session?.user.id;
      userEmail = session?.user.email;
    }

    if (userId == null) {
      setState(() => _saving = false);
      _showSnack('Session expired. Please login again.');
      if (mounted) context.go('/login');
      return;
    }

    final name = _passedName.isNotEmpty ? _passedName : 'User';
    final email = _passedEmail.isNotEmpty ? _passedEmail : (userEmail ?? '');

    // Safety net: make sure `profiles` has name + email (signup already
    // does this, but this covers any edge case where it didn't land yet).
    // Only real `profiles` columns are written — never onboarding data.
    await ProfileService.upsertProfile(userId, fullName: name, email: email);

    // Every onboarding answer, plus the computed persona and
    // onboarding_completed flag, is saved into the `onboarding` table.
    final success = await OnboardingService.saveOnboarding(userId, _data);

    if (!mounted) return;
    setState(() => _saving = false);

    if (!success) {
      _showSnack('Could not save your answers. Please check your connection and try again.');
      return;
    }

    final persona = _data.classifyPersona();
    debugPrint('✅ Onboarding complete — persona: $persona');

    // Fetch every persona_dataset row matching this persona and keep it in
    // memory (PersonaDatasetProvider) for later analysis.
    if (mounted) {
      await context.read<PersonaDatasetProvider>().loadForPersona(persona);
    }

    if (mounted) context.read<AuthProvider>().markOnboardingComplete();
    HapticFeedback.mediumImpact();
    _goTo(_kTotalPages - 1);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final showChrome = _currentPage != 0 && _currentPage != _kTotalPages - 1;

    return PopScope(
      canPop: _currentPage == 0,
      onPopInvoked: (didPop) {
        if (!didPop && _currentPage > 0) _previous();
      },
      child: Scaffold(
        backgroundColor: AppTheme.bg(isDark),
        body: SafeArea(
          child: Column(
            children: [
              // ── Top bar: back + progress + skip ─────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: showChrome
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: _previous,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppTheme.glass(isDark),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppTheme.border(isDark)),
                                ),
                                child: Icon(Icons.arrow_back_ios_new_rounded,
                                    size: 15, color: AppTheme.fg(isDark)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OnboardingProgressBar(
                                currentStep: _currentPage - _kFirstQuestionStep,
                                totalSteps: _kLastQuestionStep - _kFirstQuestionStep + 1,
                                isDark: isDark,
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 44,
                              child: _currentPage < _kLastQuestionStep
                                  ? GestureDetector(
                                      onTap: _skip,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                        child: Text('Skip',
                                            style: TextStyle(
                                                color: AppTheme.muted(isDark),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13.5)),
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),

              // ── Page content ─────────────────────────────────────────────
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    _WelcomeStep(isDark: isDark, name: _passedName, onStart: _next),
                    _SingleSelectStep(
                      isDark: isDark,
                      emoji: '💼',
                      title: 'What best describes your\ncurrent profession?',
                      options: const [
                        ('🎓', 'Student'),
                        ('💼', 'Salaried Employee'),
                        ('🏢', 'Business Owner'),
                        ('💻', 'Freelancer'),
                        ('🏠', 'Homemaker'),
                        ('👴', 'Retired'),
                        ('🔹', 'Other'),
                      ],
                      selected: _data.profession,
                      onSelected: (v) => setState(() => _data.profession = v),
                    ),
                    _SingleSelectStep(
                      isDark: isDark,
                      emoji: '💵',
                      title: 'How do you usually earn\nyour income?',
                      options: const [
                        ('💰', 'Fixed Monthly Income'),
                        ('📈', 'Variable Income'),
                        ('❌', 'No Regular Income'),
                      ],
                      selected: _data.incomeType,
                      onSelected: (v) => setState(() => _data.incomeType = v),
                    ),
                    _IncomeStep(
                      isDark: isDark,
                      controller: _incomeCtrl,
                      onChanged: (v) => setState(() => _data.monthlyIncome = double.tryParse(v)),
                    ),
                    _FixedExpensesStep(
                      isDark: isDark,
                      selected: _data.fixedExpenses,
                      onToggle: (v) => setState(() {
                        _data.fixedExpenses.contains(v)
                            ? _data.fixedExpenses.remove(v)
                            : _data.fixedExpenses.add(v);
                      }),
                    ),
                    _SpendingHabitStep(
                      isDark: isDark,
                      selected: _data.spendingHabit,
                      onSelected: (v) => setState(() => _data.spendingHabit = v),
                    ),
                    _SingleSelectStep(
                      isDark: isDark,
                      emoji: '🎯',
                      title: 'What is your biggest\nfinancial goal?',
                      options: const [
                        ('💰', 'Save More Money'),
                        ('❤️', 'Build Emergency Fund'),
                        ('🏠', 'Buy a House'),
                        ('🚗', 'Buy a Car'),
                        ('✈️', 'Travel'),
                        ('📈', 'Invest More'),
                        ('💳', 'Become Debt Free'),
                        ('🎓', 'Education'),
                        ('🔹', 'Other'),
                      ],
                      selected: _data.financialGoal,
                      onSelected: (v) => setState(() => _data.financialGoal = v),
                    ),
                    _SingleSelectStep(
                      isDark: isDark,
                      emoji: '💸',
                      title: 'How much of your monthly\nincome do you usually save?',
                      options: const [
                        ('🌱', '0–10%'),
                        ('🌿', '10–20%'),
                        ('🌳', '20–30%'),
                        ('🌲', '30–50%'),
                        ('🏆', 'More than 50%'),
                      ],
                      selected: _data.savingPercentage,
                      onSelected: (v) => setState(() => _data.savingPercentage = v),
                    ),
                    _SingleSelectStep(
                      isDark: isDark,
                      emoji: '⚠️',
                      title: 'How often do you exceed\nyour monthly budget?',
                      options: const [
                        ('😊', 'Never'),
                        ('🙂', 'Rarely'),
                        ('😐', 'Sometimes'),
                        ('😬', 'Often'),
                        ('😅', 'Almost Every Month'),
                      ],
                      selected: _data.budgetDiscipline,
                      onSelected: (v) => setState(() => _data.budgetDiscipline = v),
                    ),
                    _SingleSelectStep(
                      isDark: isDark,
                      emoji: '📒',
                      title: 'How often do you track\nyour expenses?',
                      options: const [
                        ('📅', 'Daily'),
                        ('🗓', 'Weekly'),
                        ('📆', 'Monthly'),
                        ('❌', 'Never'),
                      ],
                      selected: _data.expenseTrackingFrequency,
                      onSelected: (v) => setState(() => _data.expenseTrackingFrequency = v),
                    ),
                    _AiAssistantStep(
                      isDark: isDark,
                      enabled: _data.aiBudgetAssistant,
                      onChanged: (v) => setState(() => _data.aiBudgetAssistant = v),
                    ),
                    _FinalStep(isDark: isDark, persona: _data.classifyPersona()),
                  ],
                ),
              ),

              // ── Bottom nav buttons ────────────────────────────────────────
              if (showChrome)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Row(
                    children: [
                      if (_currentPage > _kFirstQuestionStep)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _previous,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: AppTheme.border(isDark)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text('Previous',
                                style: TextStyle(
                                    color: AppTheme.fg(isDark), fontWeight: FontWeight.w600)),
                          ),
                        ),
                      if (_currentPage > _kFirstQuestionStep) const SizedBox(width: 12),
                      Expanded(
                        flex: _currentPage > _kFirstQuestionStep ? 1 : 2,
                        child: GradientButton(
                          label: _currentPage == _kLastQuestionStep ? 'Finish' : 'Next',
                          icon: _currentPage == _kLastQuestionStep
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                          loading: _saving,
                          onPressed: _next,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_currentPage == _kTotalPages - 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                  child: GradientButton(
                    label: '✨ Continue to Dashboard',
                    onPressed: () => context.go('/dashboard'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// STEP WIDGETS
// ════════════════════════════════════════════════════════════════════════

class _WelcomeStep extends StatelessWidget {
  final bool isDark;
  final String name;
  final VoidCallback onStart;
  const _WelcomeStep({required this.isDark, required this.name, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, AppTheme.teal],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(color: AppTheme.primary.withOpacity(0.35), blurRadius: 30, offset: const Offset(0, 12)),
              ],
            ),
            child: const Center(child: Text('👋', style: TextStyle(fontSize: 54))),
          ).animate().scale(duration: 500.ms, curve: Curves.elasticOut).fadeIn(duration: 300.ms),
          const SizedBox(height: 36),
          Text(
            name.isNotEmpty ? 'Welcome, $name! 💰' : 'Welcome to Finora 💰',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.fg(isDark), height: 1.3),
          ).animate().fadeIn(delay: 150.ms, duration: 400.ms).slideY(begin: 0.15, end: 0),
          const SizedBox(height: 14),
          Text(
            "Let's understand your financial lifestyle so we can personalize your budgeting, spending analysis, and savings journey.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: AppTheme.muted(isDark), height: 1.5),
          ).animate().fadeIn(delay: 250.ms, duration: 400.ms).slideY(begin: 0.15, end: 0),
          const SizedBox(height: 44),
          GradientButton(label: "🚀 Let's Get Started", onPressed: onStart)
              .animate()
              .fadeIn(delay: 400.ms, duration: 400.ms)
              .slideY(begin: 0.2, end: 0),
        ],
      ),
    );
  }
}

class _SingleSelectStep extends StatelessWidget {
  final bool isDark;
  final String emoji;
  final String title;
  final List<(String, String)> options;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _SingleSelectStep({
    required this.isDark,
    required this.emoji,
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OnboardingHeader(title: title, isDark: isDark),
          const SizedBox(height: 26),
          ...List.generate(options.length, (i) {
            final (icon, label) = options[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OnboardingOptionCard(
                emoji: icon,
                label: label,
                selected: selected == label,
                isDark: isDark,
                onTap: () => onSelected(label),
              ),
            ).animate().fadeIn(delay: (40 * i).ms, duration: 300.ms).slideX(begin: 0.06, end: 0);
          }),
        ],
      ),
    );
  }
}

class _IncomeStep extends StatelessWidget {
  final bool isDark;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _IncomeStep({required this.isDark, required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OnboardingHeader(
            title: 'What is your average\nmonthly income?',
            description: "This helps Finora tailor budgets that actually fit your life.",
            isDark: isDark,
          ),
          const SizedBox(height: 30),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface(isDark),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.border(isDark)),
              boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(colors: [AppTheme.primary, AppTheme.teal]).createShader(b),
                  child: const Text('₹', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    keyboardType: const TextInputType.numberWithOptions(decimal: false),
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppTheme.fg(isDark)),
                    decoration: InputDecoration(
                      hintText: '50,000',
                      hintStyle: TextStyle(color: AppTheme.muted(isDark), fontWeight: FontWeight.w600),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1, end: 0),
          const SizedBox(height: 10),
          Text('Example: ₹50,000', style: TextStyle(fontSize: 12.5, color: AppTheme.muted(isDark))),
        ],
      ),
    );
  }
}

class _FixedExpensesStep extends StatelessWidget {
  final bool isDark;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const _FixedExpensesStep({required this.isDark, required this.selected, required this.onToggle});

  static const _options = [
    ('🏠', 'Rent'),
    ('💳', 'Home Loan EMI'),
    ('💳', 'Personal Loan EMI'),
    ('💳', 'Credit Card Bill'),
    ('💡', 'Electricity Bill'),
    ('🚰', 'Water Bill'),
    ('📶', 'Internet / Mobile'),
    ('🛡', 'Insurance'),
    ('🎓', 'Education Fees'),
    ('🚗', 'Vehicle EMI'),
    ('🔹', 'Other'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OnboardingHeader(
            title: 'Which of these expenses\ndo you pay every month?',
            description: 'Select all that apply — this stays accurate as your bills change.',
            isDark: isDark,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(_options.length, (i) {
              final (icon, label) = _options[i];
              return OnboardingMultiSelectChip(
                emoji: icon,
                label: label,
                selected: selected.contains(label),
                isDark: isDark,
                onTap: () => onToggle(label),
              ).animate().fadeIn(delay: (30 * i).ms, duration: 250.ms).scale(begin: const Offset(0.9, 0.9));
            }),
          ),
        ],
      ),
    );
  }
}

class _SpendingHabitStep extends StatelessWidget {
  final bool isDark;
  final String? selected;
  final ValueChanged<String> onSelected;
  const _SpendingHabitStep({required this.isDark, required this.selected, required this.onSelected});

  static const _options = [
    ('💰', 'Consistent Saver', 'I carefully follow my budget and save regularly.'),
    ('⚖️', 'Balanced Planner', 'I usually stay within my budget but sometimes spend extra.'),
    ('🛍️', 'Lifestyle Spender', 'I enjoy shopping, dining, and entertainment.'),
    ('🎲', 'Irregular Spender', 'My expenses are unpredictable and change every month.'),
    ('💳', 'Loan & EMI Focused', 'A significant part of my income goes toward EMIs and bills.'),
    ('🎯', 'Goal-Oriented Saver', "I'm actively saving for an important financial goal."),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OnboardingHeader(title: 'Which statement best\ndescribes your spending habit?', isDark: isDark),
          const SizedBox(height: 24),
          ...List.generate(_options.length, (i) {
            final (icon, label, subtitle) = _options[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OnboardingOptionCard(
                emoji: icon,
                label: label,
                subtitle: subtitle,
                selected: selected == label,
                isDark: isDark,
                onTap: () => onSelected(label),
              ),
            ).animate().fadeIn(delay: (50 * i).ms, duration: 300.ms).slideX(begin: 0.06, end: 0);
          }),
        ],
      ),
    );
  }
}

class _AiAssistantStep extends StatelessWidget {
  final bool isDark;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _AiAssistantStep({required this.isDark, required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OnboardingHeader(
            title: 'Want an AI Budget\nAssistant? 🤖',
            description: 'AI will analyze your spending habits and help you stay within your budget.',
            isDark: isDark,
          ),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primary.withOpacity(0.14), AppTheme.teal.withOpacity(0.08)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.border(isDark)),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.teal]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(child: Text('🤖', style: TextStyle(fontSize: 26))),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Smart spending insights',
                          style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.fg(isDark), fontSize: 15)),
                      const SizedBox(height: 3),
                      Text('Get proactive nudges before you overspend',
                          style: TextStyle(fontSize: 12.5, color: AppTheme.muted(isDark))),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  activeColor: AppTheme.primary,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    onChanged(v);
                  },
                ),
              ],
            ),
          ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1, end: 0),
        ],
      ),
    );
  }
}

class _FinalStep extends StatelessWidget {
  final bool isDark;
  final String persona;
  const _FinalStep({required this.isDark, required this.persona});

  @override
  Widget build(BuildContext context) {
    final emoji = OnboardingData.personaEmojis[persona] ?? '💰';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppTheme.success, AppTheme.teal]),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppTheme.success.withOpacity(0.35), blurRadius: 34, offset: const Offset(0, 14))],
            ),
            child: const Center(child: Icon(Icons.check_rounded, color: Colors.white, size: 64)),
          ).animate().scale(duration: 550.ms, curve: Curves.elasticOut).fadeIn(duration: 300.ms),
          const SizedBox(height: 30),
          const Text('🎉 You\'re all set!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold))
              .animate()
              .fadeIn(delay: 150.ms, duration: 400.ms)
              .slideY(begin: 0.15, end: 0),
          const SizedBox(height: 12),
          Text(
            "We're creating your personalized financial profile based on your answers.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: AppTheme.muted(isDark), height: 1.5),
          ).animate().fadeIn(delay: 250.ms, duration: 400.ms).slideY(begin: 0.15, end: 0),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.glass(isDark),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border(isDark)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Flexible(
                  child: Text('Your persona: $persona',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.fg(isDark), fontSize: 14)),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 400.ms, duration: 400.ms).scale(begin: const Offset(0.9, 0.9)),
        ],
      ),
    );
  }
}
