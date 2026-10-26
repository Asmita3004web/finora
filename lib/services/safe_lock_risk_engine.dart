import 'package:finora/models/expense.dart';
import 'package:finora/utils/finance_utils.dart';

enum SafetyLevel { safe, caution, highRisk }

/// Result of one risk evaluation — everything here is derived from the
/// real expense list passed in. There are no hard-coded percentages: every
/// threshold below is a judgement call on how to *interpret* real numbers
/// (e.g. "a category is over 45% of monthly spend"), not a fabricated
/// statistic standing in for one.
class SafetyAssessment {
  final SafetyLevel level;
  final double score; // 0.0 (perfectly safe) .. 1.0 (maximum risk)
  final List<String> reasons;

  const SafetyAssessment({
    required this.level,
    required this.score,
    required this.reasons,
  });

  static const empty = SafetyAssessment(level: SafetyLevel.safe, score: 0, reasons: []);
}

/// Evaluates real spending data for SafeLock. No network/Supabase calls —
/// this only ever looks at data already loaded by the caller, so it can be
/// re-run on every screen build or after every expense save without cost.
class SafeLockRiskEngine {
  /// [budgetLimit] is the user's effective monthly budget (savings-goal
  /// based budget limit, falling back to 0 if never set). [monthlyIncome]
  /// is optional context used only to phrase the "approaching limit"
  /// reason more usefully; it never gates risk on its own.
  static SafetyAssessment evaluate({
    required List<Expense> expenses,
    required double budgetLimit,
  }) {
    if (expenses.isEmpty) return SafetyAssessment.empty;

    final reasons = <String>[];
    double score = 0;

    final monthlySpend = FinanceUtils.getMonthlySpending(expenses);
    final weekSpend = FinanceUtils.getWeekSpending(expenses);
    final categories = FinanceUtils.getCategoryTotals(expenses);

    // ── 1. Budget limit being approached / exceeded ─────────────────────
    if (budgetLimit > 0) {
      final ratio = monthlySpend / budgetLimit;
      if (ratio >= 1.0) {
        reasons.add('Monthly budget limit already exceeded');
        score += 0.4;
      } else if (ratio >= 0.85) {
        reasons.add('Budget limit is being approached (${(ratio * 100).round()}% used)');
        score += 0.25;
      }
    }

    // ── 2. High concentration in one category ───────────────────────────
    if (monthlySpend > 0 && categories.isNotEmpty) {
      final top = categories.entries.reduce((a, b) => a.value > b.value ? a : b);
      final topShare = top.value / monthlySpend;
      if (topShare >= 0.45) {
        reasons.add('High spending in one category (${top.key}, ${(topShare * 100).round()}% of this month)');
        score += 0.2;
      }
    }

    // ── 3. Recent spending unusually high vs. this user's own average ──
    // Compares this week's real spend against this user's real average
    // weekly spend over however much history they have (never a made-up
    // benchmark), so a brand-new user with one big week isn't flagged
    // off a single data point.
    final weeksOfHistory = _weeksSpanned(expenses);
    if (weeksOfHistory >= 2) {
      final avgWeekly = monthlySpend > 0
          ? _averageWeeklySpend(expenses)
          : 0.0;
      if (avgWeekly > 0 && weekSpend > avgWeekly * 1.4) {
        final overPct = (((weekSpend - avgWeekly) / avgWeekly) * 100).round();
        reasons.add('This week\'s spending is $overPct% above your recent average');
        score += 0.2;
      }
    }

    // ── 4. Multiple expenses in a short period ──────────────────────────
    final todayCount = expenses.where((e) => e.date == FinanceUtils.toDateKey(DateTime.now())).length;
    if (todayCount >= 4) {
      reasons.add('$todayCount separate expenses logged today');
      score += 0.15;
    }

    // ── 5. Large, unexpected single expense ─────────────────────────────
    if (expenses.length >= 5) {
      final avgTxn = expenses.fold(0.0, (s, e) => s + e.amount) / expenses.length;
      final mostRecent = expenses.first; // callers keep this newest-first
      if (avgTxn > 0 && mostRecent.amount > avgTxn * 3) {
        reasons.add(
          'Large unexpected expense (₹${mostRecent.amount.toStringAsFixed(0)} vs your usual ₹${avgTxn.toStringAsFixed(0)})',
        );
        score += 0.25;
      }
    }

    score = score.clamp(0.0, 1.0);
    final level = score >= 0.6
        ? SafetyLevel.highRisk
        : score >= 0.3
            ? SafetyLevel.caution
            : SafetyLevel.safe;

    return SafetyAssessment(level: level, score: score, reasons: reasons);
  }

  static int _weeksSpanned(List<Expense> expenses) {
    final dates = expenses.map((e) => DateTime.tryParse(e.date)).whereType<DateTime>().toList();
    if (dates.isEmpty) return 0;
    dates.sort();
    return (dates.last.difference(dates.first).inDays / 7).ceil().clamp(0, 9999);
  }

  static double _averageWeeklySpend(List<Expense> expenses) {
    final weeks = _weeksSpanned(expenses).clamp(1, 9999);
    final total = expenses.fold(0.0, (s, e) => s + e.amount);
    return total / weeks;
  }
}
