import 'dart:math' as math;
import 'package:finora/models/analysis_result.dart';
import 'package:finora/models/expense.dart';
import 'package:finora/models/onboarding_record.dart';

/// Centralised, persona-aware financial analysis.
///
///   persona (onboarding.persona)  ┐
///   transactions (Expense/Income) ├─►  analyze()  ─►  AnalysisResult  ─►  Analysis screen
///   budget / goal / onboarding    ┘
///
/// This is plain, deterministic arithmetic over the user's real rows — it is
/// NOT six ML models. The persona only decides *which* calculations and
/// wording are shown. All inputs are passed in (the screen already fetched
/// them once), so this class makes no Supabase calls of its own and never
/// duplicates a query.
class PersonaAnalysisService {
  PersonaAnalysisService._();

  static const consistentSaver = 'Consistent Saver';
  static const balancedPlanner = 'Balanced Planner';
  static const lifestyleSpender = 'Lifestyle Spender';
  static const irregularSpender = 'Irregular Spender';
  static const loanEmiFocused = 'Loan & EMI Focused';
  static const goalOrientedSaver = 'Goal-Oriented Saver';

  static const personas = [
    consistentSaver,
    balancedPlanner,
    lifestyleSpender,
    irregularSpender,
    loanEmiFocused,
    goalOrientedSaver,
  ];

  /// Minimum transactions in the selected period before persona analysis
  /// is shown. Below this we say "Not enough data yet".
  static const minTransactions = 5;

  /// Maps the stored string onto one of the six canonical names
  /// (case/whitespace-insensitive). Returns null if it isn't one of them.
  static String? normalizePersona(String? raw) {
    if (raw == null) return null;
    final t = raw.trim().toLowerCase();
    for (final p in personas) {
      if (p.toLowerCase() == t) return p;
    }
    return null;
  }

  // ───────────────────────────────────────────────────────────────────────
  // Entry point
  // ───────────────────────────────────────────────────────────────────────

  /// [expenses] / [incomes]: all of the user's transactions (any period).
  /// [budgetLimit]: spending_locks.budget_limit (monthly), null if unset.
  /// [savingsGoal]: BudgetLimits.savingsGoal (monthly savings target).
  static AnalysisResult analyze({
    required String? persona,
    required OnboardingRecord? onboarding,
    required List<Expense> expenses,
    required List<Expense> incomes,
    required double? budgetLimit,
    required double savingsGoal,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double monthsCovered,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final p = normalizePersona(persona);

    final inPeriod = _inRange(expenses, periodStart, periodEnd);
    final incomeInPeriod = _inRange(incomes, periodStart, periodEnd);
    final declared = onboarding?.monthlyIncome ?? 0;

    final common = _common(
      inPeriod: inPeriod,
      allExpenses: expenses,
      allIncomes: incomes,
      incomeInPeriod: incomeInPeriod,
      declaredMonthlyIncome: declared,
      budgetLimit: budgetLimit,
      monthsCovered: monthsCovered,
      today: today,
    );

    final ctx = _Ctx(
      common: common,
      inPeriod: inPeriod,
      onboarding: onboarding,
      savingsGoal: savingsGoal,
      monthsCovered: monthsCovered,
      today: today,
    );

    PersonaSection section;
    List<String> recs;

    if (p == null) {
      section = const PersonaSection.empty(
        title: 'Persona Analysis',
        message: 'No persona found for this account yet. Complete onboarding to '
            'unlock persona-based analysis.',
      );
      recs = const [];
    } else if (inPeriod.length < minTransactions) {
      section = PersonaSection.empty(
        title: _titleFor(p),
        message: 'Not enough data yet. Add at least $minTransactions transactions in '
            'this period (you have ${inPeriod.length}).',
      );
      recs = const [];
    } else {
      final analyzer = _analyzers[p];
      if (analyzer == null) {
        // Persona is valid but its analysis isn't built yet — say so rather
        // than showing generic numbers dressed up as persona analysis.
        section = PersonaSection.empty(
          title: _titleFor(p),
          message: 'Persona-specific analysis for "$p" is not available yet. '
              'Your overall financial overview is shown above.',
        );
        recs = const [];
      } else {
        (section, recs) = analyzer(ctx);
      }
    }

    return AnalysisResult(
      persona: p,
      common: common,
      section: section,
      recommendations: recs,
    );
  }

  /// Persona -> analysis function. Add an entry here when another persona's
  /// analysis is implemented; nothing else in the pipeline needs to change.
  static final Map<String, (PersonaSection, List<String>) Function(_Ctx)> _analyzers = {
    consistentSaver: _consistentSaver,
    balancedPlanner: _balancedPlanner,
    lifestyleSpender: _lifestyleSpender,
    irregularSpender: _irregularSpender,
    loanEmiFocused: _loanEmi,
    goalOrientedSaver: _goalOriented,
  };

  /// True when a persona-specific analysis exists for [persona].
  static bool hasAnalysis(String? persona) {
    final p = normalizePersona(persona);
    return p != null && _analyzers.containsKey(p);
  }

  static String _titleFor(String p) {
    switch (p) {
      case consistentSaver:
        return 'Savings Consistency';
      case balancedPlanner:
        return 'Budget & Balance';
      case lifestyleSpender:
        return 'Lifestyle Spending';
      case irregularSpender:
        return 'Spending Volatility';
      case loanEmiFocused:
        return 'EMI & Debt Load';
      case goalOrientedSaver:
        return 'Goal Progress';
      default:
        return 'Persona Analysis';
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Common metrics (identical for every persona)
  // ───────────────────────────────────────────────────────────────────────

  static CommonMetrics _common({
    required List<Expense> inPeriod,
    required List<Expense> allExpenses,
    required List<Expense> allIncomes,
    required List<Expense> incomeInPeriod,
    required double declaredMonthlyIncome,
    required double? budgetLimit,
    required double monthsCovered,
    required DateTime today,
  }) {
    final totalExpenses = _sum(inPeriod);

    // Income: real Income rows win; otherwise the declared onboarding income.
    double? totalIncome;
    String source;
    final actualIncome = _sum(incomeInPeriod);
    if (actualIncome > 0) {
      totalIncome = actualIncome;
      source = 'transactions';
    } else if (declaredMonthlyIncome > 0) {
      totalIncome = declaredMonthlyIncome * monthsCovered;
      source = 'declared';
    } else {
      totalIncome = null;
      source = 'none';
    }

    final savings = totalIncome == null ? null : totalIncome - totalExpenses;
    final savingsRate = (totalIncome != null && totalIncome > 0)
        ? savings! / totalIncome * 100
        : null;

    final cats = _byCategory(inPeriod);
    String? topCat;
    double? topShare;
    if (cats.isNotEmpty && totalExpenses > 0) {
      final top = (cats.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;
      topCat = top.key;
      topShare = top.value / totalExpenses * 100;
    }

    final fixed = inPeriod.where((e) => e.isSubscription).fold(0.0, (s, e) => s + e.amount);
    final fixedTracked = allExpenses.any((e) => e.isSubscription);

    // Budget usage: current calendar month's spend vs the monthly budget.
    double? budgetUsed;
    if (budgetLimit != null && budgetLimit > 0) {
      final key = _monthKey(today);
      final monthSpend = _sum(allExpenses.where((e) => _keyOf(e.date) == key));
      budgetUsed = monthSpend / budgetLimit * 100;
    }

    final trend = _monthlySeries(allExpenses, allIncomes, declaredMonthlyIncome, today);

    return CommonMetrics(
      totalIncome: totalIncome,
      incomeSource: source,
      totalExpenses: totalExpenses,
      savings: savings,
      savingsRate: savingsRate,
      avgPerTransaction: inPeriod.isEmpty ? 0 : totalExpenses / inPeriod.length,
      avgPerMonth: monthsCovered > 0 ? totalExpenses / monthsCovered : totalExpenses,
      topCategory: topCat,
      topCategoryShare: topShare,
      transactionCount: inPeriod.length,
      fixedTracked: fixedTracked,
      fixedTotal: fixed,
      variableTotal: totalExpenses - fixed,
      budgetLimit: (budgetLimit != null && budgetLimit > 0) ? budgetLimit : null,
      budgetUsedPercent: budgetUsed,
      monthlyTrend: trend,
    );
  }

  /// Trailing (max 6) calendar months from the user's first expense to today.
  static List<MonthlyTotal> _monthlySeries(
    List<Expense> expenses,
    List<Expense> incomes,
    double declared,
    DateTime today,
  ) {
    if (expenses.isEmpty) return const [];
    DateTime? first;
    for (final e in expenses) {
      final d = DateTime.tryParse(e.date);
      if (d != null && (first == null || d.isBefore(first))) first = d;
    }
    if (first == null) return const [];

    final spend = <String, double>{};
    for (final e in expenses) {
      final k = _keyOf(e.date);
      if (k != null) spend[k] = (spend[k] ?? 0) + e.amount;
    }
    final inc = <String, double>{};
    for (final e in incomes) {
      final k = _keyOf(e.date);
      if (k != null) inc[k] = (inc[k] ?? 0) + e.amount;
    }

    final months = <MonthlyTotal>[];
    var cursor = DateTime(first.year, first.month, 1);
    final end = DateTime(today.year, today.month, 1);
    while (!cursor.isAfter(end)) {
      final k = _monthKey(cursor);
      final actual = inc[k] ?? 0;
      final income = actual > 0 ? actual : (declared > 0 ? declared : null);
      months.add(MonthlyTotal(key: k, expense: spend[k] ?? 0, income: income));
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return months.length > 6 ? months.sublist(months.length - 6) : months;
  }

  /// Months used for "consistency/variation" maths: drops the in-progress
  /// current month when at least two finished months exist, so a half-done
  /// month doesn't look like a sudden drop in spending.
  static List<MonthlyTotal> _completeMonths(List<MonthlyTotal> series, DateTime today) {
    final currentKey = _monthKey(today);
    final done = series.where((m) => m.key != currentKey && m.expense > 0).toList();
    if (done.length >= 2) return done;
    return series.where((m) => m.expense > 0).toList();
  }

  // ───────────────────────────────────────────────────────────────────────
  // Persona analyses
  // ───────────────────────────────────────────────────────────────────────

  /// Consistent Saver analysis.
  ///
  /// "Savings" is only computed where an income figure exists for the month:
  /// real `Income` transactions when present, otherwise the monthly income
  /// declared at onboarding (flagged as an estimate in [PersonaSection.note]).
  /// With no income information at all, no savings numbers are produced.
  static (PersonaSection, List<String>) _consistentSaver(_Ctx c) {
    const title = 'Savings Consistency';
    final common = c.common;

    if (common.totalIncome == null) {
      return (
        const PersonaSection.empty(
          title: title,
          message: 'Not enough data yet. Savings can\'t be calculated without an '
              'income figure (onboarding monthly income or Income transactions).',
        ),
        const <String>[],
      );
    }

    final months = _completeMonths(common.monthlyTrend, c.today)
        .where((m) => m.savings != null)
        .toList();
    if (months.length < 2) {
      return (
        const PersonaSection.empty(
          title: title,
          message: 'Not enough data yet. Savings consistency needs transactions '
              'from at least 2 different months.',
        ),
        const <String>[],
      );
    }

    final total = common.totalExpenses;
    final positive = months.where((m) => m.savings! > 0).length;
    final avgSavings = months.fold(0.0, (s, m) => s + m.savings!) / months.length;
    final cv = _cv(months.map((m) => m.expense).toList());
    final rate = common.savingsRate;
    final cats = _byCategory(c.inPeriod).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final disc = _sumCats(c.inPeriod, _discretionary);
    final discShare = total > 0 ? disc / total * 100 : 0.0;

    // Transactions per week across the days actually covered by the data.
    final dates = c.inPeriod.map((e) => DateTime.tryParse(e.date)).whereType<DateTime>().toList()
      ..sort();
    final spanDays = dates.isEmpty ? 1 : dates.last.difference(dates.first).inDays + 1;
    final perWeek = c.inPeriod.length / (spanDays / 7).clamp(1, 100000);

    final consistent = positive == months.length;
    final controlled = cv != null && cv <= 0.25;

    String insight;
    if (consistent && controlled) {
      insight = 'Your saving behaviour is consistent and your expenses are well controlled.';
    } else if (consistent) {
      insight = 'You saved in every month analysed, though monthly expenses vary a little.';
    } else {
      insight = 'You saved in $positive of ${months.length} months analysed — '
          'savings have been uneven.';
    }

    final strengths = <String>[];
    final watch = <String>[];
    if (consistent) strengths.add('Positive savings in every month analysed');
    if (rate != null && rate >= 20) strengths.add('Savings rate of ${_pct(rate)} this period');
    if (controlled) strengths.add('Monthly expenses stay within a narrow range');
    if (discShare > 0 && discShare < 20) strengths.add('Shopping & entertainment are only ${_pct(discShare)} of spending');
    if (!consistent) watch.add('${months.length - positive} month(s) ended with no savings');
    if (cv != null && cv > 0.25) watch.add('Monthly expenses vary by about ${_pct(cv * 100)}');
    if (discShare >= 30) watch.add('Shopping & entertainment are ${_pct(discShare)} of spending');
    if (rate != null && rate < 10) watch.add('Savings rate is ${_pct(rate)} this period');

    // Opportunities: only categories that exist in the data, and phrased as
    // a "what if", not a promise.
    final opportunities = <String>[];
    for (final e in cats.where((e) => _discretionary.contains(e.key)).take(2)) {
      final cut = e.value * 0.10;
      if (cut >= 1) {
        opportunities.add('Reducing ${e.key} by 10% would free about ${_inr(cut)} over this period.');
      }
    }
    if (cats.isNotEmpty && !_discretionary.contains(cats.first.key) && total > 0) {
      opportunities.add('${cats.first.key} is your largest category (${_pct(cats.first.value / total * 100)} of spending) — worth a look for savings.');
    }

    final recs = <String>[];
    if (!consistent) {
      recs.add('Set aside your savings at the start of the month so a higher-spend month doesn\'t reduce it.');
    }
    if (cv != null && cv > 0.25) {
      recs.add('Monthly spending swings by ${_pct(cv * 100)} — a fixed monthly spending limit could steady your savings.');
    }
    if (discShare >= 30) {
      recs.add('Shopping & entertainment make up ${_pct(discShare)} of spending — a small cap there is the easiest lever.');
    }
    if (consistent && controlled) {
      recs.add('Your pattern is steady — consider moving part of the monthly surplus into a longer-term investment.');
    }
    if (recs.isEmpty) recs.add('Keep logging expenses — more history makes this analysis more reliable.');

    final declared = common.incomeSource == 'declared';

    return (
      PersonaSection(
        title: title,
        insight: insight,
        note: declared
            ? 'Savings are estimated from the monthly income you declared during '
                'onboarding, since no Income transactions were found.'
            : null,
        metrics: [
          AnalysisMetric('Savings rate', rate == null ? 'Not enough data yet' : _pct(rate)),
          AnalysisMetric('Avg monthly savings', _inr(avgSavings), hint: '${months.length} months'),
          AnalysisMetric('Months with savings', '$positive of ${months.length}'),
          AnalysisMetric('Spending consistency',
              cv == null ? '—' : '±${_pct(cv * 100)}',
              hint: 'month-to-month variation'),
          AnalysisMetric('Transaction frequency', '${perWeek.toStringAsFixed(1)} / week'),
          AnalysisMetric('Discretionary share', _pct(discShare), hint: 'Shopping + Entertainment'),
        ],
        strengths: strengths,
        watch: watch,
        opportunities: opportunities,
        barsTitle: 'Monthly savings trend',
        bars: [
          for (final m in months) AnalysisBar(_monthLabel(m.key), m.savings!, _inr(m.savings!)),
        ],
        bars2Title: 'Highest spending categories',
        bars2: [
          for (final e in cats.take(4))
            AnalysisBar(e.key, e.value, '${_inr(e.value)} · ${_pct(total > 0 ? e.value / total * 100 : 0)}'),
        ],
      ),
      recs,
    );
  }

  /// Balanced Planner analysis: income vs expenses, remaining balance, fixed
  /// vs variable split, category balance, month-to-month consistency and
  /// budget balance.
  ///
  /// Formulas (all over the selected period unless stated):
  ///   remaining balance   = income - expenses
  ///   savings rate        = remaining balance / income x 100
  ///   expense ratio       = expenses / income x 100
  ///   top-category share  = largest category / expenses x 100
  ///   consistency         = std-dev / mean of monthly expenses (complete months)
  ///   budget used         = this month's spend / spending_locks.budget_limit
  ///   projected month-end = month spend / days elapsed x days in month
  ///                         (only once at least 7 days of the month have passed)
  /// Income is real Income rows if present, else the onboarding-declared
  /// monthly income (flagged as an estimate). No income -> no balance maths.
  static (PersonaSection, List<String>) _balancedPlanner(_Ctx c) {
    const title = 'Budget & Balance';
    final common = c.common;
    final income = common.totalIncome;

    if (income == null || income <= 0) {
      return (
        const PersonaSection.empty(
          title: title,
          message: 'Not enough data yet. Balance analysis needs an income figure '
              '(onboarding monthly income or Income transactions).',
        ),
        const <String>[],
      );
    }

    final total = common.totalExpenses;
    final months = c.monthsCovered > 0 ? c.monthsCovered : 1.0;
    final remaining = income - total;
    final expenseRatio = total / income * 100;
    final savingsRate = remaining / income * 100;

    final cats = _byCategory(c.inPeriod).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topShare = common.topCategoryShare ?? 0;
    final balancedCats = cats.length >= 3 && topShare <= 40;

    final complete = _completeMonths(common.monthlyTrend, c.today);
    final cv = _cv(complete.map((m) => m.expense).toList());
    String consistencyLabel = 'Not enough data yet';
    if (cv != null) {
      consistencyLabel = cv <= 0.15
          ? 'Very steady (±${_pct(cv * 100)})'
          : cv <= 0.30
              ? 'Moderate (±${_pct(cv * 100)})'
              : 'Variable (±${_pct(cv * 100)})';
    }

    // Budget balance for the current calendar month.
    final limit = common.budgetLimit;
    final usedPct = common.budgetUsedPercent;
    double? projected;
    String budgetValue = 'No monthly budget set';
    String? budgetHint;
    if (limit != null && usedPct != null) {
      final monthSpend = limit * usedPct / 100;
      budgetValue = '${_pct(usedPct)} used';
      budgetHint = '${_inr(monthSpend)} of ${_inr(limit)} this month';
      if (c.today.day >= 7) {
        final daysInMonth = DateTime(c.today.year, c.today.month + 1, 0).day;
        projected = monthSpend / c.today.day * daysInMonth;
      }
    }
    final overspendRisk = projected != null && limit != null && projected > limit;

    final fixedShare = (common.fixedTracked && total > 0) ? common.fixedTotal / total * 100 : null;

    String insight;
    if (remaining < 0) {
      insight = 'Your expenses were higher than your income in this period.';
    } else if (overspendRisk) {
      insight = 'At the current pace you may go over this month\'s budget.';
    } else if (balancedCats && expenseRatio <= 90) {
      insight = 'Your income and expenses are relatively balanced across major categories.';
    } else if (!balancedCats && common.topCategory != null) {
      insight = '${common.topCategory} makes up ${_pct(topShare)} of your spending, '
          'so your budget leans on one category.';
    } else {
      insight = 'You are spending ${_pct(expenseRatio)} of your income this period.';
    }

    final strengths = <String>[];
    final watch = <String>[];
    if (remaining >= 0 && expenseRatio <= 85) strengths.add('Spending is ${_pct(expenseRatio)} of income');
    if (savingsRate >= 20) strengths.add('Savings rate of ${_pct(savingsRate)} this period');
    if (balancedCats) strengths.add('No single category dominates (top: ${_pct(topShare)})');
    if (cv != null && cv <= 0.15) strengths.add('Monthly spending is steady');
    if (usedPct != null && usedPct <= 80) strengths.add('Within budget so far this month (${_pct(usedPct)} used)');

    if (remaining < 0) watch.add('Expenses exceed income by ${_inr(-remaining)}');
    if (remaining >= 0 && savingsRate < 10) watch.add('Savings rate is ${_pct(savingsRate)}');
    if (!balancedCats && common.topCategory != null) {
      watch.add('${common.topCategory} is ${_pct(topShare)} of spending');
    }
    if (cv != null && cv > 0.30) watch.add('Monthly spending varies by about ${_pct(cv * 100)}');
    if (usedPct != null && usedPct >= 100) {
      watch.add('Monthly budget exceeded (${_pct(usedPct)} used)');
    } else if (usedPct != null && usedPct >= 80) {
      watch.add('${_pct(usedPct)} of the monthly budget is already used');
    }
    if (overspendRisk) {
      watch.add('Projected month-end spend is ${_inr(projected!)} against a ${_inr(limit!)} budget');
    }

    // Opportunities: grounded in the user's own category totals.
    final opportunities = <String>[];
    final targetSavings = income * 0.20;
    final gapPerMonth = (targetSavings - (remaining > 0 ? remaining : 0)) / months;
    if (remaining < targetSavings && gapPerMonth >= 1) {
      opportunities.add('Reaching the common 20%-of-income savings guideline would mean '
          'about ${_inr(gapPerMonth)} less spending per month.');
    }
    final variable = common.fixedTracked ? common.variableTotal : total;
    if (cats.isNotEmpty && total > 0) {
      final top = cats.first;
      final cut = top.value * 0.10 / months;
      if (cut >= 1) {
        opportunities.add('Trimming ${top.key} by 10% would free about ${_inr(cut)} per month.');
      }
    }

    final recs = <String>[];
    if (remaining < 0) {
      recs.add('Spending is above income — review ${common.topCategory ?? 'your largest category'} first, since it has the most room.');
    }
    if (overspendRisk) {
      final daysLeft = DateTime(c.today.year, c.today.month + 1, 0).day - c.today.day;
      final room = limit! - (limit * usedPct! / 100);
      if (daysLeft > 0 && room > 0) {
        recs.add('To stay within budget, keep daily spending near ${_inr(room / daysLeft)} for the remaining $daysLeft days.');
      } else {
        recs.add('The monthly budget is already used up — hold non-essential spending until next month.');
      }
    }
    if (remaining >= 0 && savingsRate < 20) {
      recs.add('Moving savings out first (target ~20% of income) leaves the rest to budget across categories.');
    }
    if (!balancedCats && common.topCategory != null) {
      recs.add('Check whether ${common.topCategory} spending matches your priorities, or set a limit for it.');
    }
    if (!common.fixedTracked && variable > 0) {
      recs.add('Mark recurring bills as fixed expenses to see how much of your spending is flexible.');
    }
    if (limit == null) {
      recs.add('Setting a monthly budget in SafeLock lets this analysis track budget balance for you.');
    }
    if (recs.isEmpty) recs.add('Your balance looks healthy — keep logging expenses so trends stay accurate.');

    final notes = <String>[
      if (common.incomeSource == 'declared')
        'Balance and savings are estimated from the monthly income you declared during onboarding, since no Income transactions were found.',
      if (!common.fixedTracked)
        'Fixed vs variable is not shown because no expenses are marked as fixed.',
    ];

    return (
      PersonaSection(
        title: title,
        insight: insight,
        note: notes.isEmpty ? null : notes.join(' '),
        metrics: [
          AnalysisMetric('Remaining balance', _inr(remaining),
              hint: common.incomeSource == 'declared' ? 'estimated' : 'income - expenses'),
          AnalysisMetric('Savings rate', _pct(savingsRate)),
          AnalysisMetric('Expenses vs income', _pct(expenseRatio), hint: 'of income spent'),
          AnalysisMetric('Budget balance', budgetValue, hint: budgetHint),
          AnalysisMetric('Spending consistency', consistencyLabel, hint: 'month to month'),
          AnalysisMetric('Category balance', balancedCats ? 'Balanced' : 'Concentrated',
              hint: '${cats.length} categories'),
          AnalysisMetric('Fixed vs variable',
              fixedShare == null ? 'Not tracked' : '${_pct(fixedShare)} / ${_pct(100 - fixedShare)}'),
        ],
        strengths: strengths,
        watch: watch,
        opportunities: opportunities,
        barsTitle: 'Spending by category',
        bars: [
          for (final e in cats.take(5))
            AnalysisBar(e.key, e.value, '${_inr(e.value)} · ${_pct(total > 0 ? e.value / total * 100 : 0)}'),
        ],
        bars2Title: fixedShare != null ? 'Fixed vs variable' : 'Spending by month',
        bars2: fixedShare != null
            ? [
                AnalysisBar('Fixed', common.fixedTotal, _inr(common.fixedTotal)),
                AnalysisBar('Variable', common.variableTotal, _inr(common.variableTotal)),
              ]
            : [
                for (final m in complete) AnalysisBar(_monthLabel(m.key), m.expense, _inr(m.expense)),
              ],
      ),
      recs,
    );
  }

  /// Lifestyle Spender analysis.
  ///
  /// Lifestyle categories are matched by keyword on the category name
  /// (see [_lifestyleKeywords]) because the app and its datasets use
  /// different category vocabularies (Shopping / Fashion / Restaurants ...).
  /// Plain "Food" and "Groceries" are NOT counted as lifestyle: "Food" can't
  /// separate dining from groceries, so counting it would overstate lifestyle.
  /// Savings / Investment rows are transfers, not consumption, so they are
  /// excluded from "spending" and shown separately.
  ///
  ///   spending          = expenses - savings/investment transfers
  ///   lifestyle share   = lifestyle spending / spending
  ///   lifestyle vs inc. = lifestyle spending / income
  ///   left after spend. = income - spending  (includes money moved to savings)
  ///   trend             = last complete month vs the one before it
  /// Conclusions come only from these numbers; a Lifestyle Spender with a
  /// low lifestyle share is reported as such.
  static (PersonaSection, List<String>) _lifestyleSpender(_Ctx c) {
    const title = 'Lifestyle Spending';
    final common = c.common;
    final months = c.monthsCovered > 0 ? c.monthsCovered : 1.0;

    final spendRows = c.inPeriod.where((e) => !_isTransfer(e.category)).toList();
    final transfers = _sum(c.inPeriod.where((e) => _isTransfer(e.category)));
    final spending = _sum(spendRows);
    if (spendRows.isEmpty || spending <= 0) {
      return (
        const PersonaSection.empty(
          title: title,
          message: 'Not enough data yet. Lifestyle analysis needs spending '
              'transactions (savings and investment transfers are not counted).',
        ),
        const <String>[],
      );
    }

    final lifeRows = spendRows.where((e) => _isLifestyle(e.category)).toList();
    final lifestyle = _sum(lifeRows);
    final share = lifestyle / spending * 100;
    final lifeCats = _byCategory(lifeRows).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final allCats = _byCategory(spendRows).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final inc = common.totalIncome ?? 0.0;
    final hasIncome = inc > 0;
    final incomeShare = hasIncome ? lifestyle / inc * 100 : null;
    final leftover = hasIncome ? inc - spending : null;
    final savingsRate = hasIncome ? (inc - spending) / inc * 100 : null;

    // Monthly lifestyle trend (complete months only, when possible).
    final spendByMonth = <String, double>{};
    final lifeByMonth = <String, double>{};
    for (final e in spendRows) {
      final k = _keyOf(e.date);
      if (k == null) continue;
      spendByMonth[k] = (spendByMonth[k] ?? 0) + e.amount;
      if (_isLifestyle(e.category)) lifeByMonth[k] = (lifeByMonth[k] ?? 0) + e.amount;
    }
    final keys = spendByMonth.keys.toList()..sort();
    final done = keys.where((k) => k != _monthKey(c.today)).toList();
    final trendKeys = done.length >= 2 ? done : keys;
    double? change;
    String? trendHint;
    if (trendKeys.length >= 2) {
      final last = trendKeys.last;
      final prev = trendKeys[trendKeys.length - 2];
      final lastV = lifeByMonth[last] ?? 0;
      final prevV = lifeByMonth[prev] ?? 0;
      if (prevV > 0) change = (lastV - prevV) / prevV * 100;
      trendHint = '${_monthLabel(prev)} to ${_monthLabel(last)}';
    }

    // Fixed vs variable, excluding transfers (transfers are often flagged fixed).
    final fixedSpend = _sum(spendRows.where((e) => e.isSubscription));
    final fixedShare = (common.fixedTracked && spending > 0) ? fixedSpend / spending * 100 : null;
    final variableSpend = spending - fixedSpend;
    final lifeVariable = _sum(lifeRows.where((e) => !e.isSubscription));
    final lifeOfVariable =
        (common.fixedTracked && variableSpend > 0) ? lifeVariable / variableSpend * 100 : null;

    String insight;
    if (lifestyle <= 0) {
      insight = 'No lifestyle or discretionary categories were found in this period.';
    } else if (share >= 40) {
      insight = 'A significant portion of your spending is going towards lifestyle categories.';
    } else if (share >= 20) {
      insight = 'Lifestyle categories make up ${_pct(share)} of your spending — a moderate share.';
    } else {
      insight = 'Lifestyle categories are a smaller part (${_pct(share)}) of your spending.';
    }

    final strengths = <String>[];
    final watch = <String>[];
    if (lifestyle > 0 && share < 20) strengths.add('Lifestyle spending is only ${_pct(share)} of total spending');
    if (savingsRate != null && savingsRate >= 20 && share >= 20) {
      strengths.add('You still keep ${_pct(savingsRate)} of income alongside lifestyle spending');
    }
    if (change != null && change <= -10) strengths.add('Lifestyle spending fell ${_pct(-change)} in the latest month');
    if (share >= 40) watch.add('Lifestyle categories are ${_pct(share)} of spending');
    if (incomeShare != null && incomeShare >= 30) watch.add('Lifestyle spending equals ${_pct(incomeShare)} of income');
    if (change != null && change >= 20) watch.add('Lifestyle spending rose ${_pct(change)} in the latest month');
    if (leftover != null && leftover < 0) watch.add('Spending exceeded income by ${_inr(-leftover)}');
    if (savingsRate != null && savingsRate >= 0 && savingsRate < 10) {
      watch.add('Only ${_pct(savingsRate)} of income is left after spending');
    }

    final opportunities = <String>[];
    for (final e in lifeCats.take(2)) {
      final cut = e.value * 0.10 / months;
      if (cut >= 1) {
        opportunities.add('Reducing ${e.key} by 10% would free about ${_inr(cut)} per month.');
      }
    }

    final recs = <String>[];
    final avgLife = lifestyle / months;
    if (share >= 30) {
      recs.add('Your lifestyle spending averages ${_inr(avgLife)} per month — a monthly limit for these categories keeps it where you want it.');
    }
    if (lifeCats.isNotEmpty && lifestyle > 0 && lifeCats.first.value / lifestyle >= 0.5 && lifeCats.length > 1) {
      recs.add('${lifeCats.first.key} is ${_pct(lifeCats.first.value / lifestyle * 100)} of lifestyle spending — the easiest place to adjust.');
    }
    if (savingsRate != null && savingsRate < 15) {
      recs.add('Moving savings out first on payday leaves lifestyle spending to use only what remains.');
    }
    if (change != null && change >= 20) {
      recs.add('Lifestyle spending jumped recently — check whether it was a one-off or a new regular level.');
    }
    if (recs.isEmpty) {
      recs.add(lifestyle > 0
          ? 'Your lifestyle spending looks proportionate — keep logging expenses so trends stay accurate.'
          : 'Categories like shopping, dining and entertainment will appear here once you log them.');
    }

    final notes = <String>[
      if (common.incomeSource == 'declared')
        'Income-based figures are estimated from the monthly income you declared during onboarding, since no Income transactions were found.',
      if (transfers > 0)
        'Savings and investment transfers (${_inr(transfers)}) are not counted as spending.',
      if (allCats.any((e) => e.key.toLowerCase() == 'food'))
        '"Food" is not counted as lifestyle because it cannot separate dining from groceries.',
    ];

    return (
      PersonaSection(
        title: title,
        insight: insight,
        note: notes.isEmpty ? null : notes.join(' '),
        metrics: [
          AnalysisMetric('Lifestyle spending', '${_inr(lifestyle)} (${_pct(share)})', hint: 'of total spending'),
          AnalysisMetric('Lifestyle vs income',
              incomeShare == null ? 'Not enough data yet' : _pct(incomeShare)),
          AnalysisMetric('Avg monthly lifestyle', _inr(avgLife)),
          AnalysisMetric('Top lifestyle category',
              lifeCats.isEmpty ? 'None found' : lifeCats.first.key,
              hint: lifeCats.isEmpty ? null : _inr(lifeCats.first.value)),
          AnalysisMetric('Lifestyle trend',
              change == null ? 'Not enough data yet' : '${change >= 0 ? '+' : ''}${_pct(change)}',
              hint: trendHint),
          AnalysisMetric('Left after spending',
              leftover == null ? 'Not enough data yet' : _inr(leftover),
              hint: common.incomeSource == 'declared' ? 'estimated' : 'includes savings & investments'),
          AnalysisMetric('Savings rate',
              savingsRate == null ? 'Not enough data yet' : _pct(savingsRate)),
          AnalysisMetric('Fixed vs variable',
              fixedShare == null ? 'Not tracked' : '${_pct(fixedShare)} / ${_pct(100 - fixedShare)}'),
          if (lifeOfVariable != null)
            AnalysisMetric('Lifestyle of variable spend', _pct(lifeOfVariable)),
        ],
        strengths: strengths,
        watch: watch,
        opportunities: opportunities,
        barsTitle: 'Spending by category',
        bars: [
          for (final e in allCats.take(6))
            AnalysisBar(
              e.key,
              e.value,
              '${_inr(e.value)} · ${_pct(e.value / spending * 100)}${_isLifestyle(e.key) ? ' · lifestyle' : ''}',
            ),
        ],
        bars2Title: trendKeys.length >= 2 ? 'Lifestyle spending by month' : null,
        bars2: trendKeys.length >= 2
            ? [
                for (final k in trendKeys)
                  AnalysisBar(_monthLabel(k), lifeByMonth[k] ?? 0, _inr(lifeByMonth[k] ?? 0)),
              ]
            : const [],
      ),
      recs,
    );
  }

  /// Spending (savings/investment transfers excluded) grouped by yyyy-MM.
  /// `keys` are the months to use for trend maths: complete months when at
  /// least two exist, otherwise every month that has data.
  static ({Map<String, double> byMonth, List<String> keys}) _spendByMonth(
    List<Expense> rows,
    DateTime today,
  ) {
    final by = <String, double>{};
    for (final e in rows) {
      final k = _keyOf(e.date);
      if (k != null) by[k] = (by[k] ?? 0) + e.amount;
    }
    final all = by.keys.toList()..sort();
    final done = all.where((k) => k != _monthKey(today)).toList();
    return (byMonth: by, keys: done.length >= 2 ? done : all);
  }

  /// Irregular Spender analysis: how much and why spending moves around.
  ///
  ///   monthly variation   = std-dev / mean of monthly spending (complete months)
  ///   large transaction   = amount >= 3 x the median transaction
  ///   spending spike day  = a day whose total is > 2 x the average active day
  ///   longest gap         = most days between two days that had spending
  /// Savings / investment transfers are regular by nature and are ignored.
  static (PersonaSection, List<String>) _irregularSpender(_Ctx c) {
    const title = 'Spending Volatility';
    final rows = c.inPeriod.where((e) => !_isTransfer(e.category)).toList();
    final m = _spendByMonth(rows, c.today);
    if (m.keys.length < 2 || rows.length < 8) {
      return (
        const PersonaSection.empty(
          title: title,
          message: 'Not enough data yet. Volatility needs at least 8 spending '
              'transactions across 2 or more months.',
        ),
        const <String>[],
      );
    }

    final months = c.monthsCovered > 0 ? c.monthsCovered : 1.0;
    final total = _sum(rows);
    final cv = _cv([for (final k in m.keys) m.byMonth[k]!]) ?? 0.0;
    final hiKey = m.keys.reduce((a, b) => m.byMonth[a]! >= m.byMonth[b]! ? a : b);
    final loKey = m.keys.reduce((a, b) => m.byMonth[a]! <= m.byMonth[b]! ? a : b);

    final amounts = rows.map((e) => e.amount).toList()..sort();
    final median = amounts[amounts.length ~/ 2];
    final large = rows.where((e) => median > 0 && e.amount >= median * 3).toList();
    final largeTotal = _sum(large);
    final largeShare = total > 0 ? largeTotal / total * 100 : 0.0;
    final byAmount = [...rows]..sort((a, b) => b.amount.compareTo(a.amount));
    final biggest = byAmount.first;

    final daily = <String, double>{};
    for (final e in rows) {
      daily[e.date] = (daily[e.date] ?? 0) + e.amount;
    }
    final avgDay = daily.values.fold(0.0, (s, v) => s + v) / daily.length;
    final spikeDays = daily.values.where((v) => v > avgDay * 2).length;
    final dates = daily.keys.map(DateTime.tryParse).whereType<DateTime>().toList()..sort();
    var longestGap = 0;
    for (var i = 1; i < dates.length; i++) {
      longestGap = math.max(longestGap, dates[i].difference(dates[i - 1]).inDays);
    }

    final volatile = cv >= 0.3;
    String insight;
    if (volatile && largeShare >= 25) {
      insight = 'Your spending varies considerably across periods, mainly because of larger irregular expenses.';
    } else if (volatile) {
      insight = 'Your spending varies considerably from one month to the next.';
    } else {
      insight = 'Your monthly spending has been fairly steady (${_pct(cv * 100)} variation).';
    }

    final strengths = <String>[];
    final watch = <String>[];
    if (!volatile) strengths.add('Monthly spending varies by only ${_pct(cv * 100)}');
    if (largeShare < 15) strengths.add('Few unusually large transactions');
    if (volatile) watch.add('Monthly spending varies by about ${_pct(cv * 100)}');
    if (largeShare >= 25) {
      watch.add('Large transactions are ${_pct(largeShare)} of total spend (${large.length})');
    }
    if (spikeDays > 0) watch.add('$spikeDays high-spend day(s) well above your usual');

    final avgMonth = m.keys.fold(0.0, (s, k) => s + m.byMonth[k]!) / m.keys.length;
    final recs = <String>[];
    if (largeShare >= 25) {
      recs.add('Larger one-off expenses drive most of the swings — setting aside about ${_inr(largeTotal / months)} a month for irregular expenses can smooth them out.');
    }
    if (volatile) {
      recs.add('Budgeting around your average month (${_inr(avgMonth)}) makes high months easier to absorb.');
    }
    if (!volatile) recs.add('Your pattern is steady — a fixed monthly budget should work well.');

    return (
      PersonaSection(
        title: title,
        insight: insight,
        metrics: [
          AnalysisMetric('Monthly variation', _pct(cv * 100), hint: 'std. dev. / average'),
          AnalysisMetric('Highest vs lowest month',
              '${_inr(m.byMonth[hiKey]!)} / ${_inr(m.byMonth[loKey]!)}',
              hint: '${_monthLabel(hiKey)} / ${_monthLabel(loKey)}'),
          AnalysisMetric('Largest transaction', _inr(biggest.amount), hint: biggest.category),
          AnalysisMetric('Large transactions', '${large.length}', hint: '${_pct(largeShare)} of spend'),
          AnalysisMetric('Spending spikes', '$spikeDays day(s)'),
          AnalysisMetric('Longest gap', '$longestGap day(s)', hint: 'between spending days'),
        ],
        strengths: strengths,
        watch: watch,
        barsTitle: 'Spending by month',
        bars: [for (final k in m.keys) AnalysisBar(_monthLabel(k), m.byMonth[k]!, _inr(m.byMonth[k]!))],
        bars2Title: 'Largest transactions',
        bars2: [
          for (final e in byAmount.take(3)) AnalysisBar(e.category, e.amount, '${_inr(e.amount)} · ${e.date}'),
        ],
      ),
      recs,
    );
  }

  /// EMI / loan rows are found by category name ("EMI", "Home Loan", "Credit
  /// Card"...). `\bemis?\b` avoids matching words like "Premium".
  static final _emiPattern = RegExp(r'\bemis?\b');
  static bool _isEmi(String category) {
    final c = category.toLowerCase();
    return _emiPattern.hasMatch(c) ||
        c.contains('loan') ||
        c.contains('credit card') ||
        c.contains('mortgage');
  }

  /// Loan & EMI Focused analysis. Shown only when EMI/loan transactions exist.
  ///
  ///   EMI-to-income        = EMI payments / income
  ///   fixed commitments    = EMI rows + rows flagged fixed (counted once)
  ///   disposable income    = income - fixed commitments
  ///   non-essential spend  = lifestyle-category spending (see Lifestyle Spender)
  static (PersonaSection, List<String>) _loanEmi(_Ctx c) {
    const title = 'EMI & Debt Load';
    final rows = c.inPeriod.where((e) => !_isTransfer(e.category)).toList();
    final emiRows = rows.where((e) => _isEmi(e.category)).toList();

    if (emiRows.isEmpty) {
      final declared = (c.onboarding?.fixedExpenses ?? const <String>[]).where(_isEmi).toList();
      final msg = declared.isEmpty
          ? 'No EMI or loan transactions found in this period. Log EMI payments '
              'under a category such as "EMI / Loan" to see your debt load.'
          : 'No EMI or loan transactions found in this period. You listed '
              '${declared.join(', ')} during onboarding — log those payments under '
              'a category such as "EMI / Loan" to see your debt load.';
      return (PersonaSection.empty(title: title, message: msg), const <String>[]);
    }

    final common = c.common;
    final spending = _sum(rows);
    final emi = _sum(emiRows);
    final inc = common.totalIncome ?? 0.0;
    final hasIncome = inc > 0;
    final emiToIncome = hasIncome ? emi / inc * 100 : null;
    final emiShare = spending > 0 ? emi / spending * 100 : 0.0;

    final committed = _sum(rows.where((e) => _isEmi(e.category) || e.isSubscription));
    final otherFixed = committed - emi;
    final disposable = hasIncome ? inc - committed : null;
    final nonEssential = _sum(rows.where((e) => _isLifestyle(e.category)));

    String insight;
    if (emiToIncome != null && emiToIncome >= 35) {
      insight = 'A significant portion of your income is committed to loan and EMI payments.';
    } else if (emiToIncome != null && emiToIncome >= 15) {
      insight = 'Loan and EMI payments take a moderate share (${_pct(emiToIncome)}) of your income.';
    } else if (emiToIncome != null) {
      insight = 'Loan and EMI payments are a small share (${_pct(emiToIncome)}) of your income.';
    } else {
      insight = 'EMI payments are ${_pct(emiShare)} of your recorded spending.';
    }

    final strengths = <String>[];
    final watch = <String>[];
    if (emiToIncome != null && emiToIncome < 30) strengths.add('EMI-to-income ratio is ${_pct(emiToIncome)}');
    if (disposable != null && disposable / inc >= 0.4) {
      strengths.add('${_pct(disposable / inc * 100)} of income remains after fixed commitments');
    }
    if (emiToIncome != null && emiToIncome >= 35) watch.add('EMI-to-income ratio is ${_pct(emiToIncome)}');
    if (disposable != null && disposable < 0) watch.add('Commitments exceed income by ${_inr(-disposable)}');
    if (hasIncome && nonEssential / inc >= 0.2) {
      watch.add('Non-essential spending is ${_pct(nonEssential / inc * 100)} of income');
    }

    final recs = <String>[];
    if (emiToIncome != null && emiToIncome >= 35) {
      recs.add('With EMIs above about 35% of income, trimming non-essential spending can free room for faster repayment.');
    }
    if (emiToIncome != null && emiToIncome < 35 && disposable != null && disposable > 0) {
      recs.add('Part of your ${_inr(disposable)} disposable income could go towards prepaying the highest-interest loan.');
    }
    if (nonEssential > 0) {
      recs.add('Non-essential spending was ${_inr(nonEssential)} this period — the most flexible place to find room.');
    }
    if (recs.isEmpty) recs.add('Keep logging EMI payments so the debt picture stays accurate.');

    final byMonth = <String, double>{};
    for (final e in emiRows) {
      final k = _keyOf(e.date);
      if (k != null) byMonth[k] = (byMonth[k] ?? 0) + e.amount;
    }
    final monthKeys = byMonth.keys.toList()..sort();

    return (
      PersonaSection(
        title: title,
        insight: insight,
        note: common.incomeSource == 'declared'
            ? 'Income-based figures are estimated from the monthly income you declared during onboarding, since no Income transactions were found.'
            : null,
        metrics: [
          AnalysisMetric('EMI / loan payments', _inr(emi), hint: '${emiRows.length} payment(s)'),
          AnalysisMetric('EMI-to-income', emiToIncome == null ? 'Not enough data yet' : _pct(emiToIncome)),
          AnalysisMetric('Share of spending', _pct(emiShare)),
          AnalysisMetric('Fixed commitments', _inr(committed), hint: 'EMIs + fixed expenses'),
          AnalysisMetric('Disposable income', disposable == null ? 'Not enough data yet' : _inr(disposable)),
          AnalysisMetric('Non-essential spending', _inr(nonEssential), hint: 'shopping, dining, entertainment...'),
        ],
        strengths: strengths,
        watch: watch,
        barsTitle: 'Where your spending goes',
        bars: [
          AnalysisBar('EMI / loans', emi, _inr(emi)),
          if (otherFixed > 0) AnalysisBar('Other fixed', otherFixed, _inr(otherFixed)),
          AnalysisBar('Other spending', math.max(0.0, spending - committed), _inr(math.max(0.0, spending - committed))),
        ],
        bars2Title: monthKeys.length >= 2 ? 'EMI / loan payments by month' : null,
        bars2: monthKeys.length >= 2
            ? [for (final k in monthKeys) AnalysisBar(_monthLabel(k), byMonth[k]!, _inr(byMonth[k]!))]
            : const [],
      ),
      recs,
    );
  }

  /// Goal-Oriented Saver analysis. Needs real goal data: a goal from
  /// onboarding (financial_goal) AND a monthly savings target (BudgetLimits).
  ///
  ///   monthly savings = average of (income - spending) over the months used
  ///   progress        = monthly savings / monthly target
  ///   remaining       = max(0, target - monthly savings)
  /// Spending excludes savings/investment transfers (they count as saved).
  /// The app stores no total goal amount, so no "months to goal" is shown.
  static (PersonaSection, List<String>) _goalOriented(_Ctx c) {
    const title = 'Goal Progress';
    final goal = c.onboarding?.financialGoal;
    final target = c.savingsGoal;
    if (goal == null || goal.trim().isEmpty || target <= 0) {
      final msg = (goal != null && goal.trim().isNotEmpty)
          ? 'Your goal is "$goal", but no monthly savings target is set yet. '
              'Set one to see goal progress.'
          : 'No financial goal found. Set a goal and a monthly savings target to '
              'see goal progress.';
      return (PersonaSection.empty(title: title, message: msg), const <String>[]);
    }

    final rows = c.inPeriod.where((e) => !_isTransfer(e.category)).toList();
    final m = _spendByMonth(rows, c.today);
    final incomeByMonth = {for (final t in c.common.monthlyTrend) t.key: t.income};
    final usable = m.keys.where((k) => incomeByMonth[k] != null).toList();
    if (usable.isEmpty) {
      return (
        const PersonaSection.empty(
          title: title,
          message: 'Not enough data yet. Goal progress needs an income '
              '(onboarding monthly income or Income transactions).',
        ),
        const <String>[],
      );
    }

    final saved = <String, double>{for (final k in usable) k: incomeByMonth[k]! - m.byMonth[k]!};
    final monthlySaved = saved.values.fold(0.0, (s, v) => s + v) / saved.length;
    final progress = monthlySaved / target * 100;
    final remaining = math.max(0.0, target - monthlySaved);
    final transfers = _sum(c.inPeriod.where((e) => _isTransfer(e.category) && usable.contains(_keyOf(e.date))));
    final loggedPerMonth = transfers / usable.length;
    // Largest *spending* category (transfers like "Savings" are not spending).
    final catTotals = _byCategory(rows).entries.toList()..sort((x, y) => y.value.compareTo(x.value));
    final topCat = catTotals.isEmpty ? null : catTotals.first.key;

    String insight;
    if (progress >= 100) {
      insight = 'Your current saving behaviour is aligned with your financial goal.';
    } else if (progress >= 60) {
      insight = 'You are close to your monthly savings target (${_pct(progress)}).';
    } else if (progress > 0) {
      insight = 'You are currently saving ${_pct(progress)} of your monthly target.';
    } else {
      insight = 'Spending has been at or above income, so nothing is being set aside towards your goal yet.';
    }

    final strengths = <String>[];
    final watch = <String>[];
    if (progress >= 100) strengths.add('Monthly savings meet or exceed your target');
    if (progress >= 60 && progress < 100) strengths.add('Most of your monthly target is being met');
    if (saved.values.every((v) => v >= target) && saved.length >= 2) {
      strengths.add('Target met in every month analysed');
    }
    if (progress < 100) watch.add('Monthly savings are ${_inr(remaining)} short of your target');
    if (saved.values.any((v) => v < 0)) watch.add('Spending exceeded income in at least one month');

    final recs = <String>[];
    if (progress < 100) {
      recs.add('Closing the ${_inr(remaining)} monthly gap is what keeps "$goal" on track.');
      if (topCat != null) recs.add('$topCat is your largest spending category — trimming it is the quickest way to close the gap.');
    } else {
      recs.add('You are meeting your target — consider raising it to reach "$goal" sooner.');
    }

    return (
      PersonaSection(
        title: title,
        insight: insight,
        note: c.common.incomeSource == 'declared'
            ? 'Savings are estimated from the monthly income you declared during onboarding, since no Income transactions were found.'
            : null,
        metrics: [
          AnalysisMetric('Goal', goal),
          AnalysisMetric('Monthly target', _inr(target)),
          AnalysisMetric('Current monthly savings', _inr(monthlySaved), hint: '${saved.length} month(s)'),
          AnalysisMetric('Goal progress', _pct(progress.clamp(0.0, 100.0).toDouble())),
          AnalysisMetric('Remaining each month', _inr(remaining)),
          if (transfers > 0)
            AnalysisMetric('Logged savings & investments', _inr(loggedPerMonth), hint: 'per month'),
        ],
        strengths: strengths,
        watch: watch,
        barsTitle: saved.length >= 2 ? 'Savings by month' : null,
        bars: saved.length >= 2
            ? [for (final e in saved.entries) AnalysisBar(_monthLabel(e.key), e.value, _inr(e.value))]
            : const [],
        bars2Title: 'Savings vs target',
        bars2: [
          AnalysisBar('Saved / month', monthlySaved, _inr(monthlySaved)),
          AnalysisBar('Target / month', target, _inr(target)),
        ],
      ),
      recs,
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Helpers
  // ───────────────────────────────────────────────────────────────────────

  static const _discretionary = {'Shopping', 'Entertainment'};

  /// Savings / investment rows are money moved, not money consumed.
  static const _transferKeywords = ['saving', 'investment', 'mutual fund', 'recurring deposit'];
  static bool _isTransfer(String category) {
    final c = category.toLowerCase();
    return _transferKeywords.any((k) => c.contains(k));
  }

  /// Keyword match on the category name. Deliberately excludes plain
  /// "Food"/"Groceries"/"Transport"/"Bills" (essentials or ambiguous).
  static const _lifestyleKeywords = [
    'shopping', 'fashion', 'cloth', 'apparel', 'electronic', 'gadget', 'accessor',
    'beauty', 'cosmetic', 'salon', 'grooming', 'personal care', 'jewel', 'luxury', 'gift',
    'restaurant', 'dining', 'cafe', 'coffee', 'eating out', 'food delivery', 'takeaway',
    'entertain', 'movie', 'cinema', 'netflix', 'hotstar', 'spotify', 'prime video',
    'gaming', 'concert', 'events', 'party', 'hobby', 'music', 'lifestyle',
    'travel', 'trip', 'vacation', 'holiday', 'hotel', 'leisure',
  ];
  static bool _isLifestyle(String category) {
    final c = category.toLowerCase();
    if (_isTransfer(c)) return false;
    return _lifestyleKeywords.any((k) => c.contains(k));
  }


  static List<Expense> _inRange(List<Expense> list, DateTime start, DateTime end) {
    return list.where((e) {
      final d = DateTime.tryParse(e.date);
      return d != null && !d.isBefore(start) && !d.isAfter(end);
    }).toList();
  }

  static double _sum(Iterable<Expense> list) => list.fold(0.0, (s, e) => s + e.amount);

  static double _sumCats(List<Expense> list, Set<String> cats) =>
      _sum(list.where((e) => cats.contains(e.category)));

  static Map<String, double> _byCategory(List<Expense> list) {
    final m = <String, double>{};
    for (final e in list) {
      m[e.category] = (m[e.category] ?? 0) + e.amount;
    }
    return m;
  }

  /// Coefficient of variation (std dev / mean); null if <2 values or mean 0.
  static double? _cv(List<double> v) {
    if (v.length < 2) return null;
    final mean = v.reduce((a, b) => a + b) / v.length;
    if (mean <= 0) return null;
    final variance = v.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / v.length;
    return math.sqrt(variance) / mean;
  }

  static String _monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
  static String? _keyOf(String date) => date.length >= 7 ? date.substring(0, 7) : null;

  static const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _monthLabel(String key) {
    final m = int.tryParse(key.substring(5, 7)) ?? 1;
    return _mon[(m - 1).clamp(0, 11)];
  }

  static String _inr(double v) => v < 0 ? '-₹${(-v).toStringAsFixed(0)}' : '₹${v.toStringAsFixed(0)}';
  static String _pct(double v) => '${v.toStringAsFixed(0)}%';
}

class _Ctx {
  final CommonMetrics common;
  final List<Expense> inPeriod;
  final OnboardingRecord? onboarding;
  final double savingsGoal;
  final double monthsCovered;
  final DateTime today;
  const _Ctx({
    required this.common,
    required this.inPeriod,
    required this.onboarding,
    required this.savingsGoal,
    required this.monthsCovered,
    required this.today,
  });
}
