/// Structured output of [PersonaAnalysisService.analyze]. The Analysis
/// screen only renders this — it contains no analysis logic itself.
///
/// Every value is derived from real rows (transactions / onboarding /
/// spending_locks). Anything that can't be derived is `null` or absent,
/// never a placeholder number.

class AnalysisMetric {
  final String label;
  final String value;
  final String? hint;
  const AnalysisMetric(this.label, this.value, {this.hint});
}

class AnalysisBar {
  final String label;
  final double value; // may be negative (e.g. a month with negative savings)
  final String display;
  const AnalysisBar(this.label, this.value, this.display);
}

class MonthlyTotal {
  final String key; // yyyy-MM
  final double expense;
  final double? income; // null when neither income rows nor declared income exist
  const MonthlyTotal({required this.key, required this.expense, this.income});

  double? get savings => income == null ? null : income! - expense;
}

class CommonMetrics {
  final double? totalIncome;

  /// 'transactions' = summed Income rows in the period,
  /// 'declared'     = onboarding monthly income x months in the period,
  /// 'none'         = no income information at all.
  final String incomeSource;
  final double totalExpenses;
  final double? savings;
  final double? savingsRate; // percent
  final double avgPerTransaction;
  final double avgPerMonth;
  final String? topCategory;
  final double? topCategoryShare; // percent
  final int transactionCount;

  /// Fixed vs variable is only meaningful when the user flags at least one
  /// expense as fixed (transactions.is_fixed_expense).
  final bool fixedTracked;
  final double fixedTotal;
  final double variableTotal;

  /// Monthly budget from spending_locks.budget_limit (null when not set).
  final double? budgetLimit;
  final double? budgetUsedPercent; // current-month spend vs monthly budget

  final List<MonthlyTotal> monthlyTrend;

  const CommonMetrics({
    required this.totalIncome,
    required this.incomeSource,
    required this.totalExpenses,
    required this.savings,
    required this.savingsRate,
    required this.avgPerTransaction,
    required this.avgPerMonth,
    required this.topCategory,
    required this.topCategoryShare,
    required this.transactionCount,
    required this.fixedTracked,
    required this.fixedTotal,
    required this.variableTotal,
    required this.budgetLimit,
    required this.budgetUsedPercent,
    required this.monthlyTrend,
  });
}

class PersonaSection {
  final String title;
  final String? insight;
  final List<AnalysisMetric> metrics;
  final List<String> strengths;
  final List<String> watch;
  final String? barsTitle;
  final List<AnalysisBar> bars;
  final String? bars2Title;
  final List<AnalysisBar> bars2;

  /// Concrete, data-derived ideas ("If X were reduced by 10% ...").
  final List<String> opportunities;

  /// Caveat shown under the section (e.g. savings are an estimate).
  final String? note;

  /// When true the section has no numbers and shows [message] instead
  /// ("Not enough data yet", "No EMI transactions found", ...).
  final bool notEnoughData;
  final String? message;

  const PersonaSection({
    required this.title,
    this.insight,
    this.metrics = const [],
    this.strengths = const [],
    this.watch = const [],
    this.barsTitle,
    this.bars = const [],
    this.bars2Title,
    this.bars2 = const [],
    this.opportunities = const [],
    this.note,
    this.notEnoughData = false,
    this.message,
  });

  const PersonaSection.empty({required this.title, required this.message})
      : insight = null,
        metrics = const [],
        strengths = const [],
        watch = const [],
        barsTitle = null,
        bars = const [],
        bars2Title = null,
        bars2 = const [],
        opportunities = const [],
        note = null,
        notEnoughData = true;
}

class AnalysisResult {
  /// One of the six canonical persona names, or null when the user has no
  /// (recognised) persona stored.
  final String? persona;
  final CommonMetrics common;
  final PersonaSection section;
  final List<String> recommendations;

  const AnalysisResult({
    required this.persona,
    required this.common,
    required this.section,
    required this.recommendations,
  });
}
