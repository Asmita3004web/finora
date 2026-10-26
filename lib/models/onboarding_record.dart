/// A persisted row from the `onboarding` table, as read back from Supabase.
///
/// This is the *read* model (used by dashboard/profile/predictions once
/// onboarding is done). The *write* model used by the onboarding wizard
/// itself is [OnboardingData] — it builds the same columns via
/// `toOnboardingMap()`.
///
/// Column names here match the `onboarding` table exactly:
/// profession, income_type, monthly_income, fixed_expenses, spending_habit,
/// financial_goal, saving_percentage, budget_discipline,
/// expense_tracking_frequency, ai_budget_assistant, persona,
/// onboarding_completed.
class OnboardingRecord {
  final String? profession;
  final String? incomeType;
  final double monthlyIncome;
  final List<String> fixedExpenses;
  final String? spendingHabit;
  final String? financialGoal;
  final double? savingPercentage;
  final String? budgetDiscipline;
  final String? expenseTrackingFrequency;
  final bool aiBudgetAssistant;
  final String? persona;
  final bool onboardingCompleted;

  OnboardingRecord({
    this.profession,
    this.incomeType,
    this.monthlyIncome = 0,
    this.fixedExpenses = const [],
    this.spendingHabit,
    this.financialGoal,
    this.savingPercentage,
    this.budgetDiscipline,
    this.expenseTrackingFrequency,
    this.aiBudgetAssistant = true,
    this.persona,
    this.onboardingCompleted = false,
  });

  factory OnboardingRecord.fromMap(Map<String, dynamic> map) {
    return OnboardingRecord(
      profession: map['profession'] as String?,
      incomeType: map['income_type'] as String?,
      monthlyIncome: double.tryParse(map['monthly_income']?.toString() ?? '') ?? 0,
      // `onboarding.fixed_expenses` is stored as a JSONB OBJECT
      // (e.g. {"Rent": true, "EMI": true}) — see `toOnboardingMap()` in
      // OnboardingData — never as a JSON array. Supabase therefore hands
      // this back as a Map<String, dynamic>, not a List. The previous
      // `map['fixed_expenses'] as List?` cast threw a TypeError on every
      // real row (silently caught by OnboardingService.getOnboarding,
      // which then returned null — making the dashboard think onboarding
      // was never completed and bounce in an invisible redirect loop).
      // Handle both shapes defensively so this never throws again.
      fixedExpenses: _parseFixedExpenses(map['fixed_expenses']),
      spendingHabit: map['spending_habit'] as String?,
      financialGoal: map['financial_goal'] as String?,
      // `saving_percentage` is a numeric column, so Supabase returns a
      // num (int/double), not a String — parse it defensively via
      // toString() rather than casting, so this never throws regardless
      // of whether Postgres hands back an int, a double, or a numeric
      // encoded as a string.
      savingPercentage: double.tryParse(map['saving_percentage']?.toString() ?? ''),
      budgetDiscipline: map['budget_discipline'] as String?,
      expenseTrackingFrequency: map['expense_tracking_frequency'] as String?,
      aiBudgetAssistant: map['ai_budget_assistant'] as bool? ?? true,
      persona: map['persona'] as String?,
      onboardingCompleted: map['onboarding_completed'] as bool? ?? false,
    );
  }

  /// `profiles` no longer carries a `user_type` column — "student" status is
  /// derived from the onboarding answer instead.
  bool get isStudent => profession == 'Student';

  /// Parses `fixed_expenses` regardless of whether Supabase hands it back
  /// as a JSON object (`{"Rent": true}`, the real shape written by
  /// `OnboardingData.toOnboardingMap()`) or, defensively, as a JSON array
  /// (`["Rent"]`), so a stray legacy row can never crash this parser.
  static List<String> _parseFixedExpenses(dynamic raw) {
    if (raw == null) return const [];
    if (raw is Map) {
      // Object shape: keys are the selected categories.
      return raw.entries
          .where((e) => e.value == true)
          .map((e) => e.key.toString())
          .toList();
    }
    if (raw is List) {
      // Defensive fallback for any legacy/array-shaped rows.
      return raw.map((e) => e.toString()).toList();
    }
    return const [];
  }
}
