import 'package:finora/models/expense.dart';
import 'package:finora/models/onboarding_record.dart';
import 'package:finora/utils/finance_utils.dart';

/// Lightweight, on-device heuristics that stand in for the AI/ML layer
/// referenced by the dashboard design (persona confidence, financial
/// health score, budget-prediction warning, primary insight).
///
/// Nothing here talks to Supabase — every number is derived from data the
/// app already has (onboarding answers, expenses, budget limits). This is
/// a clearly separated placeholder: none of these values are hard-coded
/// into the UI, and the whole thing can be swapped for a real AI service
/// later without touching any screen.
class AiInsightsService {
  /// Rough confidence (0-98%) that the detected persona label is correct.
  /// Placeholder: scales with how complete the onboarding answers are and
  /// how many matching `persona_dataset` rows back the persona, so it
  /// still returns a sensible baseline even with zero dataset rows.
  static int personaConfidence({
    required OnboardingRecord onboarding,
    required int datasetRowCount,
  }) {
    double score = 60;
    if ((onboarding.persona ?? '').isNotEmpty) score += 10;
    if (onboarding.financialGoal != null) score += 5;
    if (onboarding.spendingHabit != null) score += 5;
    if (onboarding.savingPercentage != null) score += 5;
    score += datasetRowCount.clamp(0, 5) * 3;
    return score.clamp(0, 98).round();
  }

  /// 0-100 "financial health" placeholder derived from how this month's
  /// predicted spending compares to the user's effective monthly budget.
  static int healthScore({
    required double monthlyBudget,
    required double predictedSpend,
  }) {
    if (monthlyBudget <= 0) return 70; // no budget set yet — neutral default
    final ratio = predictedSpend / monthlyBudget;
    double score;
    if (ratio <= 0.7) {
      score = 90 + (0.7 - ratio).clamp(0, 0.7) * 14; // strong saver
    } else if (ratio <= 1.0) {
      score = 70 + (1.0 - ratio) * 66; // on track
    } else {
      score = 70 - (ratio - 1.0).clamp(0, 1) * 60; // overspending
    }
    return score.clamp(0, 100).round();
  }

  /// Effective "monthly budget" for the AI prediction card. Falls back to
  /// the user's stated monthly income when no explicit budget/savings goal
  /// has been set yet, so the card never shows ₹0.
  static double effectiveMonthlyBudget({
    required double savingsGoal,
    required double monthlyIncome,
  }) {
    if (savingsGoal > 0) return savingsGoal;
    return monthlyIncome;
  }

  /// Short natural-language insight for the "AI Insight" card. Reuses the
  /// existing FinanceUtils.getSmartInsights() so the message is grounded
  /// in the user's real category spending rather than hard-coded text.
  static String primaryInsight(
    List<Expense> expenses,
    OnboardingRecord onboarding,
  ) {
    final insights = FinanceUtils.getSmartInsights(expenses, onboarding);
    return insights.isNotEmpty
        ? insights.first
        : 'Start logging expenses to unlock personalized AI insights.';
  }

  /// Budget-prediction warning shown under the AI Budget Prediction card's
  /// progress bar. Returns null when there's nothing to warn about.
  static String? budgetWarning({
    required double predictedSpend,
    required double monthlyBudget,
  }) {
    if (monthlyBudget <= 0) return null;
    final diff = predictedSpend - monthlyBudget;
    if (diff <= 0) return null;
    return 'You may exceed your budget by ₹${diff.toStringAsFixed(0)}.';
  }
}
