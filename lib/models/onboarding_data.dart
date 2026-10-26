/// Holds every answer collected during the Finora onboarding flow
/// and knows how to turn itself into a row for the `onboarding` table
/// plus a spending persona.
///
/// This is the *write* model used only by the onboarding wizard screen.
/// `toOnboardingMap()` produces the exact column names of the `onboarding`
/// table — nothing here is ever saved into `profiles`.
class OnboardingData {
  String? profession;
  String? incomeType;
  double? monthlyIncome;
  final Set<String> fixedExpenses = {};
  String? spendingHabit;
  String? financialGoal;
  String? savingPercentage;
  String? budgetDiscipline;
  String? expenseTrackingFrequency;
  bool aiBudgetAssistant = true;

  /// Simple per-step completion checks used to gate the Next button.
  bool isStepValid(int step) {
    switch (step) {
      case 0: // Welcome
        return true;
      case 1: // Profession
        return profession != null;
      case 2: // Income type
        return incomeType != null;
      case 3: // Monthly income
        return monthlyIncome != null && monthlyIncome! > 0;
      case 4: // Fixed expenses (optional - "none" is a valid answer)
        return true;
      case 5: // Spending habit
        return spendingHabit != null;
      case 6: // Financial goal
        return financialGoal != null;
      case 7: // Saving percentage
        return savingPercentage != null;
      case 8: // Budget discipline
        return budgetDiscipline != null;
      case 9: // Expense tracking frequency
        return expenseTrackingFrequency != null;
      case 10: // AI budget assistant toggle
        return true;
      case 11: // Final / success screen
        return true;
      default:
        return true;
    }
  }

  /// Payload for insert/upsert into the `onboarding` table. `user_id` is
  /// added by the service layer, which is the only place that knows the
  /// signed-in user's id.
  ///
  /// `saving_percentage` is a `numeric` column in the real database, but
  /// the onboarding UI collects it as a bucketed string ('0–10%',
  /// '10–20%', ...) — see [savingPercentage]. [_savingPercentageNumeric]
  /// converts that bucket to its midpoint percentage (a plain number)
  /// before it's sent to Supabase, so we never try to write text into a
  /// numeric column.
  Map<String, dynamic> toOnboardingMap() {
    return {
      'profession': profession,
      'income_type': incomeType,
      'monthly_income': monthlyIncome ?? 0,
      // `onboarding.fixed_expenses` is a JSONB column that expects a JSON
      // OBJECT (e.g. {"Rent": true, "EMI": true}), not a JSON array. The
      // wizard only collects which categories are toggled on (no amounts),
      // so each selected category is mapped to `true`.
      'fixed_expenses': {for (final e in fixedExpenses) e: true},
      'spending_habit': spendingHabit,
      'financial_goal': financialGoal,
      'saving_percentage': _savingPercentageNumeric,
      'budget_discipline': budgetDiscipline,
      'expense_tracking_frequency': expenseTrackingFrequency,
      'ai_budget_assistant': aiBudgetAssistant,
      'persona': classifyPersona(),
      'onboarding_completed': true,
    };
  }

  // Midpoint of each savings-percentage bucket shown in the onboarding UI.
  // Used only to translate the bucket into the numeric value the
  // `onboarding.saving_percentage` column actually expects.
  static const Map<String, double> _savingPercentageBucketMidpoints = {
    '0–10%': 5,
    '10–20%': 15,
    '20–30%': 25,
    '30–50%': 40,
    'More than 50%': 60,
  };

  /// Numeric equivalent of [savingPercentage], or `null` if the user
  /// hasn't answered that step yet. This — never the raw bucket string —
  /// is what gets saved to the `onboarding.saving_percentage` column.
  double? get _savingPercentageNumeric {
    final bucket = savingPercentage;
    if (bucket == null) return null;

    // Bucket text is the normal case (from the picker UI). Fall back to
    // parsing a plain number in case this field is ever set directly to a
    // numeric string instead of a bucket label.
    return _savingPercentageBucketMidpoints[bucket] ?? double.tryParse(bucket);
  }

  /// Classifies the user into one of six personas.
  ///
  /// Step 6 ("Spending Habit") already asks the user to self-select the
  /// persona that resonates most, so that is the strongest single signal.
  /// We still cross-check it against a few objective signals (EMI load,
  /// savings rate, budget discipline) so an answer that doesn't match the
  /// rest of the profile gets gently corrected — this is the bit of
  /// "smart" classification the AI assistant relies on later.
  String classifyPersona() {
    final emiCount = fixedExpenses
        .where((e) => e.contains('EMI') || e.contains('Loan') || e.contains('Credit Card'))
        .length;

    // Heavy EMI/loan load dominates regardless of self-reported habit.
    if (emiCount >= 3 ||
        (emiCount >= 2 &&
            (budgetDiscipline == 'Often' || budgetDiscipline == 'Almost Every Month'))) {
      return 'Loan & EMI Focused';
    }

    // Strong, disciplined saver with a named goal.
    if ((savingPercentage == '30–50%' || savingPercentage == 'More than 50%') &&
        (financialGoal != null && financialGoal != 'Save More Money')) {
      return 'Goal-Oriented Saver';
    }

    // High savings rate + tight tracking + rarely over budget.
    if ((savingPercentage == '20–30%' ||
            savingPercentage == '30–50%' ||
            savingPercentage == 'More than 50%') &&
        (expenseTrackingFrequency == 'Daily' || expenseTrackingFrequency == 'Weekly') &&
        (budgetDiscipline == 'Never' || budgetDiscipline == 'Rarely')) {
      return 'Consistent Saver';
    }

    // Frequently over budget with unpredictable tracking.
    if ((budgetDiscipline == 'Often' || budgetDiscipline == 'Almost Every Month') &&
        (expenseTrackingFrequency == 'Never' || expenseTrackingFrequency == 'Monthly')) {
      return 'Irregular Spender';
    }

    // Fall back to whatever the user told us directly in Step 6.
    if (spendingHabit != null) return spendingHabit!;

    return 'Balanced Planner';
  }

  static const Map<String, String> personaEmojis = {
    'Consistent Saver': '💰',
    'Balanced Planner': '⚖️',
    'Lifestyle Spender': '🛍️',
    'Irregular Spender': '🎲',
    'Loan & EMI Focused': '💳',
    'Goal-Oriented Saver': '🎯',
  };
}
