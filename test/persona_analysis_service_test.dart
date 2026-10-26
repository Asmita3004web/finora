import 'package:flutter_test/flutter_test.dart';
import 'package:finora/models/analysis_result.dart';
import 'package:finora/models/expense.dart';
import 'package:finora/models/onboarding_record.dart';
import 'package:finora/services/persona_analysis_service.dart';

Expense _e(String id, String date, double amount, [String category = 'Food', bool fixed = false]) =>
    Expense(
      id: id,
      date: date,
      amount: amount,
      category: category,
      mood: 'Neutral',
      paymentMode: 'UPI',
      isSubscription: fixed,
    );

/// 5 expenses in [month] (yyyy-MM) summing to [total].
List<Expense> _month(String month, double total, {String prefix = ''}) => [
      for (var i = 1; i <= 5; i++)
        _e('$prefix$month-$i', '$month-${(i * 4).toString().padLeft(2, '0')}', total / 5,
            i == 5 ? 'Shopping' : 'Food'),
    ];

final _now = DateTime(2026, 10, 11);
final _onb = OnboardingRecord(monthlyIncome: 50000, persona: 'Consistent Saver');

AnalysisResult _run(
  List<Expense> expenses, {
  OnboardingRecord? onboarding,
  List<Expense> incomes = const [],
  String? persona = 'Consistent Saver',
  double? budgetLimit,
  double savingsGoal = 0,
}) =>
    PersonaAnalysisService.analyze(
      persona: persona,
      onboarding: onboarding ?? _onb,
      expenses: expenses,
      incomes: incomes,
      budgetLimit: budgetLimit,
      savingsGoal: savingsGoal,
      periodStart: DateTime(2026, 8, 1),
      periodEnd: DateTime(2026, 10, 31),
      monthsCovered: 3,
      now: _now,
    );

void main() {
  test('sufficient history: real numbers, consistent insight', () {
    final data = [
      ..._month('2026-08', 20000),
      ..._month('2026-09', 21000),
      ..._month('2026-10', 19000),
    ];
    final r = _run(data);
    expect(r.persona, 'Consistent Saver');
    expect(r.common.totalExpenses, 60000);
    expect(r.common.totalIncome, 150000); // declared 50k x 3 months
    expect(r.common.incomeSource, 'declared');
    expect(r.common.savings, 90000);
    expect(r.common.savingsRate, closeTo(60, 0.001));
    expect(r.common.transactionCount, 15);
    expect(r.section.notEnoughData, isFalse);
    expect(r.section.insight,
        'Your saving behaviour is consistent and your expenses are well controlled.');
    // Aug + Sep are the complete months: savings 30000 and 29000.
    expect(r.section.bars.map((b) => b.value), [30000, 29000]);
    expect(r.section.note, isNotNull); // declared-income caveat is shown
    expect(r.recommendations, isNotEmpty);
  });

  test('no transactions: no invented trends', () {
    final r = _run(const []);
    expect(r.common.totalExpenses, 0);
    expect(r.common.transactionCount, 0);
    expect(r.common.monthlyTrend, isEmpty);
    expect(r.section.notEnoughData, isTrue);
    expect(r.section.message, contains('Not enough data yet'));
  });

  test('insufficient history: too few transactions', () {
    final r = _run([_e('1', '2026-10-02', 100), _e('2', '2026-10-03', 200), _e('3', '2026-10-04', 50)]);
    expect(r.section.notEnoughData, isTrue);
    expect(r.section.message, contains('you have 3'));
  });

  test('insufficient history: only one month of data', () {
    final r = _run(_month('2026-10', 20000));
    expect(r.section.notEnoughData, isTrue);
    expect(r.section.message, contains('2 different months'));
  });

  test('no income information: savings are not computed', () {
    final r = _run(
      [..._month('2026-08', 20000), ..._month('2026-09', 21000)],
      onboarding: OnboardingRecord(monthlyIncome: 0, persona: 'Consistent Saver'),
    );
    expect(r.common.totalIncome, isNull);
    expect(r.common.savings, isNull);
    expect(r.common.savingsRate, isNull);
    expect(r.section.notEnoughData, isTrue);
  });

  test('real Income transactions take priority over declared income', () {
    final r = _run(
      [..._month('2026-08', 20000), ..._month('2026-09', 21000)],
      incomes: [_e('i1', '2026-08-01', 40000, 'Salary'), _e('i2', '2026-09-01', 40000, 'Salary')],
    );
    expect(r.common.incomeSource, 'transactions');
    expect(r.common.totalIncome, 80000);
    expect(r.section.note, isNull);
  });

  test('adding an expense changes the result', () {
    final base = [..._month('2026-08', 20000), ..._month('2026-09', 21000)];
    final before = _run(base);
    final after = _run([...base, _e('new', '2026-10-05', 5000, 'Shopping')]);
    expect(after.common.transactionCount, before.common.transactionCount + 1);
    expect(after.common.totalExpenses, before.common.totalExpenses + 5000);
  });

  test('persona comes from stored value, not email; unknown personas are handled', () {
    expect(PersonaAnalysisService.normalizePersona(' consistent saver '), 'Consistent Saver');
    expect(PersonaAnalysisService.normalizePersona('Something Else'), isNull);
    final r = _run(_month('2026-09', 20000), persona: 'Balanced Planner');
    expect(r.persona, 'Balanced Planner');
    expect(r.section.notEnoughData, isFalse);
  });

  // ───────────────────────── Balanced Planner ─────────────────────────

  group('Balanced Planner', () {
    const bp = 'Balanced Planner';
    final bpOnb = OnboardingRecord(monthlyIncome: 50000, persona: bp);

    /// One txn per category: Food 6000, Transport 4000, Shopping 5000,
    /// Bills 5000 (= 20000 / month, 4 categories, none above 40%).
    List<Expense> mix(String month, {bool billsFixed = false}) => [
          _e('$month-f', '$month-03', 6000, 'Food'),
          _e('$month-t', '$month-07', 4000, 'Transport'),
          _e('$month-s', '$month-12', 5000, 'Shopping'),
          _e('$month-b', '$month-15', 5000, 'Bills', billsFixed),
        ];

    AnalysisResult run(List<Expense> ex,
            {OnboardingRecord? onb, double? budget, List<Expense> incomes = const []}) =>
        _run(ex, persona: bp, onboarding: onb ?? bpOnb, budgetLimit: budget, incomes: incomes);

    String metric(AnalysisResult r, String label) =>
        r.section.metrics.firstWhere((m) => m.label == label).value;

    test('balanced data: real totals, balance, insight', () {
      final r = run([...mix('2026-08'), ...mix('2026-09'), ...mix('2026-10')]);
      expect(r.persona, bp);
      expect(r.section.notEnoughData, isFalse);
      expect(r.common.totalExpenses, 60000);
      expect(metric(r, 'Remaining balance'), '₹90000'); // 150000 declared - 60000
      expect(metric(r, 'Savings rate'), '60%');
      expect(metric(r, 'Expenses vs income'), '40%');
      expect(metric(r, 'Category balance'), 'Balanced');
      expect(metric(r, 'Spending consistency'), 'Very steady (±0%)');
      expect(metric(r, 'Budget balance'), 'No monthly budget set');
      expect(metric(r, 'Fixed vs variable'), 'Not tracked');
      expect(r.section.insight,
          'Your income and expenses are relatively balanced across major categories.');
      expect(r.section.bars.first.label, 'Food'); // largest category first
      expect(r.section.note, contains('estimated'));
      expect(r.section.note, contains('Fixed vs variable'));
    });

    test('expenses above income: negative balance, clear insight', () {
      final r = run(
        [...mix('2026-08'), ...mix('2026-09'), ...mix('2026-10')],
        onb: OnboardingRecord(monthlyIncome: 10000, persona: bp), // 30000 over 3 months
      );
      expect(metric(r, 'Remaining balance'), '-₹30000');
      expect(r.section.insight, 'Your expenses were higher than your income in this period.');
      expect(r.section.watch.any((w) => w.contains('exceed income')), isTrue);
    });

    test('zero income: no balance maths, no crash', () {
      final r = run(
        [...mix('2026-08'), ...mix('2026-09')],
        onb: OnboardingRecord(monthlyIncome: 0, persona: bp),
      );
      expect(r.common.totalIncome, isNull);
      expect(r.common.savingsRate, isNull);
      expect(r.section.notEnoughData, isTrue);
      expect(r.section.message, contains('income figure'));
    });

    test('no transactions and too few transactions', () {
      expect(run(const []).section.notEnoughData, isTrue);
      final few = run([_e('1', '2026-10-02', 100), _e('2', '2026-10-03', 200)]);
      expect(few.section.notEnoughData, isTrue);
      expect(few.section.message, contains('you have 2'));
    });

    test('single month: consistency shown as not enough data, rest still computed', () {
      final r = run(_month('2026-10', 20000));
      expect(r.section.notEnoughData, isFalse);
      expect(metric(r, 'Spending consistency'), 'Not enough data yet');
      expect(metric(r, 'Category balance'), 'Concentrated'); // only 2 categories
    });

    test('budget balance: projection and daily allowance from real month spend', () {
      // Oct (11 days elapsed in a 31-day month): 12000 spent against a 20000 budget.
      final oct = [
        _e('o1', '2026-10-02', 3000, 'Food'),
        _e('o2', '2026-10-04', 3000, 'Transport'),
        _e('o3', '2026-10-06', 3000, 'Shopping'),
        _e('o4', '2026-10-09', 3000, 'Bills'),
      ];
      final r = run([...mix('2026-08'), ...mix('2026-09'), ...oct], budget: 20000);
      expect(metric(r, 'Budget balance'), '60% used');
      // 12000 / 11 x 31 = 33818
      expect(r.section.watch.any((w) => w.contains('₹33818')), isTrue);
      expect(r.section.insight, 'At the current pace you may go over this month\'s budget.');
      // remaining room 8000 over 20 days = 400/day
      expect(r.recommendations.any((x) => x.contains('₹400')), isTrue);
    });

    test('fixed vs variable uses is_fixed_expense flags', () {
      final r = run([
        ...mix('2026-08', billsFixed: true),
        ...mix('2026-09', billsFixed: true),
        ...mix('2026-10', billsFixed: true),
      ]);
      expect(metric(r, 'Fixed vs variable'), '25% / 75%'); // 15000 / 60000
      expect(r.section.bars2Title, 'Fixed vs variable');
      expect(r.section.bars2.map((b) => b.value), [15000, 45000]);
    });

    test('date filter: expenses outside the period are excluded', () {
      final r = run([
        ...mix('2026-08'),
        ...mix('2026-09'),
        ...mix('2026-10'),
        _e('old', '2026-05-10', 99999, 'Shopping'),
      ]);
      expect(r.common.totalExpenses, 60000);
      expect(r.common.transactionCount, 12);
    });

    test('Income transactions override declared income', () {
      final r = run(
        [...mix('2026-08'), ...mix('2026-09')],
        incomes: [_e('i1', '2026-08-01', 30000, 'Salary'), _e('i2', '2026-09-01', 30000, 'Salary')],
      );
      expect(r.common.incomeSource, 'transactions');
      expect(metric(r, 'Remaining balance'), '₹20000'); // 60000 - 40000
      expect(r.section.note ?? '', isNot(contains('estimated')));
    });

    test('adding an expense updates balance', () {
      final base = [...mix('2026-08'), ...mix('2026-09')];
      final before = run(base);
      final after = run([...base, _e('new', '2026-10-05', 5000, 'Shopping')]);
      expect(after.common.totalExpenses, before.common.totalExpenses + 5000);
      expect(metric(after, 'Remaining balance') != metric(before, 'Remaining balance'), isTrue);
    });
  });

  // ───────────────────────── Lifestyle Spender ─────────────────────────

  group('Lifestyle Spender', () {
    const ls = 'Lifestyle Spender';
    final lsOnb = OnboardingRecord(monthlyIncome: 50000, persona: ls);

    /// Per month: spending 35000 (Rent 15000 fixed, Groceries 5000,
    /// Fashion 8000, Restaurants 4000, Entertainment 3000) + a 5000
    /// Savings transfer. Lifestyle = 15000.
    List<Expense> full(String m) => [
          _e('$m-rent', '$m-01', 15000, 'Rent', true),
          _e('$m-gro', '$m-03', 5000, 'Groceries'),
          _e('$m-fas', '$m-06', 8000, 'Fashion'),
          _e('$m-res', '$m-09', 4000, 'Restaurants'),
          _e('$m-ent', '$m-12', 3000, 'Entertainment'),
          _e('$m-sav', '$m-15', 5000, 'Savings', true),
        ];

    AnalysisResult run(List<Expense> ex, {OnboardingRecord? onb}) =>
        _run(ex, persona: ls, onboarding: onb ?? lsOnb);

    String metric(AnalysisResult r, String label) =>
        r.section.metrics.firstWhere((m) => m.label == label).value;

    test('lifestyle-heavy data: totals, shares, trend, opportunities', () {
      final oct = [
        _e('o-gro', '2026-10-03', 2000, 'Groceries'),
        _e('o-fas', '2026-10-05', 4000, 'Fashion'),
        _e('o-res', '2026-10-08', 2000, 'Restaurants'),
      ];
      final r = run([...full('2026-08'), ...full('2026-09'), ...oct]);
      expect(r.persona, ls);
      expect(r.section.notEnoughData, isFalse);
      // spending = 78000 (transfers of 10000 excluded), lifestyle = 36000 -> 46%
      expect(metric(r, 'Lifestyle spending'), '₹36000 (46%)');
      expect(metric(r, 'Lifestyle vs income'), '24%'); // 36000 / 150000
      expect(metric(r, 'Avg monthly lifestyle'), '₹12000');
      expect(metric(r, 'Top lifestyle category'), 'Fashion');
      expect(metric(r, 'Lifestyle trend'), '+0%'); // Aug 15000 -> Sep 15000
      expect(metric(r, 'Left after spending'), '₹72000'); // 150000 - 78000
      expect(metric(r, 'Savings rate'), '48%');
      expect(metric(r, 'Fixed vs variable'), '38% / 62%'); // rent 30000 / 78000
      expect(metric(r, 'Lifestyle of variable spend'), '75%'); // 36000 / 48000
      expect(r.section.insight,
          'A significant portion of your spending is going towards lifestyle categories.');
      expect(r.section.bars.first.label, 'Rent');
      expect(r.section.bars.first.display, isNot(contains('lifestyle')));
      expect(r.section.bars[1].display, contains('lifestyle')); // Fashion
      expect(r.section.bars2.map((b) => b.value), [15000, 15000]);
      expect(r.section.opportunities.first, contains('Fashion'));
      expect(r.section.opportunities.first, contains('₹667'));
      expect(r.section.note, contains('₹10000')); // transfers disclosed
      expect(r.recommendations.any((x) => x.contains('₹12000')), isTrue);
    });

    test('no lifestyle categories: reported as such, not assumed', () {
      final r = run([
        for (final m in ['2026-08', '2026-09']) ...[
          _e('$m-rent', '$m-01', 15000, 'Rent', true),
          _e('$m-gro', '$m-03', 5000, 'Groceries'),
          _e('$m-trn', '$m-06', 2000, 'Transport'),
          _e('$m-bil', '$m-09', 3000, 'Bills'),
        ],
      ]);
      expect(r.section.insight, 'No lifestyle or discretionary categories were found in this period.');
      expect(metric(r, 'Lifestyle spending'), '₹0 (0%)');
      expect(metric(r, 'Top lifestyle category'), 'None found');
      expect(r.section.strengths, isEmpty);
    });

    test('low lifestyle share is reported neutrally', () {
      final r = run([
        for (final m in ['2026-08', '2026-09']) ...[
          _e('$m-rent', '$m-01', 20000, 'Rent', true),
          _e('$m-gro', '$m-03', 8000, 'Groceries'),
          _e('$m-res', '$m-06', 2000, 'Restaurants'),
          _e('$m-trn', '$m-09', 1000, 'Transport'),
        ],
      ]);
      // lifestyle 4000 / spending 62000 = 6%
      expect(r.section.insight, 'Lifestyle categories are a smaller part (6%) of your spending.');
      expect(r.section.strengths.any((s) => s.contains('only 6%')), isTrue);
    });

    test('plain Food is not counted as lifestyle (and the note says why)', () {
      final r = run([
        for (final m in ['2026-08', '2026-09']) ...[
          _e('$m-rent', '$m-01', 15000, 'Rent', true),
          _e('$m-food', '$m-03', 6000, 'Food'),
          _e('$m-trn', '$m-06', 2000, 'Transport'),
          _e('$m-bil', '$m-09', 3000, 'Bills'),
        ],
      ]);
      expect(metric(r, 'Lifestyle spending'), '₹0 (0%)');
      expect(r.section.note, contains('"Food"'));
    });

    test('zero income: lifestyle figures still shown, income figures say not enough data', () {
      final r = run(
        [...full('2026-08'), ...full('2026-09')],
        onb: OnboardingRecord(monthlyIncome: 0, persona: ls),
      );
      expect(r.section.notEnoughData, isFalse);
      expect(metric(r, 'Lifestyle spending'), '₹30000 (43%)'); // 30000 / 70000
      expect(metric(r, 'Lifestyle vs income'), 'Not enough data yet');
      expect(metric(r, 'Left after spending'), 'Not enough data yet');
      expect(metric(r, 'Savings rate'), 'Not enough data yet');
    });

    test('no transactions and too few transactions', () {
      expect(run(const []).section.notEnoughData, isTrue);
      final few = run([_e('1', '2026-10-02', 100, 'Fashion'), _e('2', '2026-10-03', 200, 'Food')]);
      expect(few.section.notEnoughData, isTrue);
      expect(few.section.message, contains('you have 2'));
    });

    test('only savings transfers: nothing to analyse', () {
      final r = run([
        for (var i = 1; i <= 5; i++) _e('s$i', '2026-09-0$i', 1000, 'Savings', true),
      ]);
      expect(r.section.notEnoughData, isTrue);
      expect(r.section.message, contains('Not enough data yet'));
    });

    test('monthly trend direction drives watch/strength wording', () {
      List<Expense> month(String m, double fashion) => [
            _e('$m-rent', '$m-01', 20000, 'Rent', true),
            _e('$m-fas', '$m-06', fashion, 'Fashion'),
            _e('$m-gro', '$m-09', 5000, 'Groceries'),
          ];
      final up = run([...month('2026-08', 5000), ...month('2026-09', 8000)]);
      expect(metric(up, 'Lifestyle trend'), '+60%');
      expect(up.section.watch.any((w) => w.contains('rose 60%')), isTrue);
      expect(up.recommendations.any((x) => x.contains('jumped recently')), isTrue);

      final down = run([...month('2026-08', 10000), ...month('2026-09', 7000)]);
      expect(metric(down, 'Lifestyle trend'), '-30%');
      expect(down.section.strengths.any((s) => s.contains('fell 30%')), isTrue);
    });

    test('date filter: expenses outside the period are excluded', () {
      final r = run([
        ...full('2026-08'),
        ...full('2026-09'),
        _e('old', '2026-05-10', 99999, 'Fashion'),
      ]);
      expect(r.common.transactionCount, 12);
      expect(metric(r, 'Lifestyle spending'), '₹30000 (43%)');
    });

    test('adding an expense updates lifestyle spending', () {
      final base = [...full('2026-08'), ...full('2026-09')];
      final before = run(base);
      final after = run([...base, _e('new', '2026-10-05', 5000, 'Fashion')]);
      expect(metric(before, 'Lifestyle spending'), '₹30000 (43%)');
      expect(metric(after, 'Lifestyle spending'), '₹35000 (47%)'); // 35000 / 75000
    });

    test('is registered, and other personas are unaffected', () {
      expect(PersonaAnalysisService.hasAnalysis(ls), isTrue);
      expect(PersonaAnalysisService.hasAnalysis('Consistent Saver'), isTrue);
      expect(PersonaAnalysisService.hasAnalysis('Balanced Planner'), isTrue);
      expect(PersonaAnalysisService.hasAnalysis('Irregular Spender'), isTrue);
    });
  });

  // ───────────────────────── Irregular Spender ─────────────────────────

  group('Irregular Spender', () {
    const ir = 'Irregular Spender';
    final irOnb = OnboardingRecord(monthlyIncome: 50000, persona: ir);
    AnalysisResult run(List<Expense> ex) => _run(ex, persona: ir, onboarding: irOnb);
    String metric(AnalysisResult r, String label) =>
        r.section.metrics.firstWhere((m) => m.label == label).value;

    // Aug total 8000, Sep total 36000 (one 30000 Shopping purchase).
    final volatile = [
      _e('a1', '2026-08-03', 2000, 'Food'),
      _e('a2', '2026-08-10', 2500, 'Food'),
      _e('a3', '2026-08-17', 1500, 'Transport'),
      _e('a4', '2026-08-24', 2000, 'Food'),
      _e('s1', '2026-09-02', 2000, 'Food'),
      _e('s2', '2026-09-09', 2200, 'Food'),
      _e('s3', '2026-09-15', 30000, 'Shopping'),
      _e('s4', '2026-09-21', 1800, 'Transport'),
    ];

    List<Expense> steady() => [
          for (final m in ['2026-08', '2026-09'])
            for (var i = 0; i < 4; i++) _e('$m-$i', '$m-${(3 + i * 7).toString().padLeft(2, '0')}', 3000, 'Food'),
        ];

    test('volatile data: variation, large transactions, spikes, gap', () {
      final r = run(volatile);
      expect(r.section.notEnoughData, isFalse);
      expect(metric(r, 'Monthly variation'), '64%'); // std 14000 / mean 22000
      expect(metric(r, 'Highest vs lowest month'), '₹36000 / ₹8000');
      expect(metric(r, 'Largest transaction'), '₹30000');
      expect(metric(r, 'Large transactions'), '1'); // >= 3 x median (2000)
      expect(metric(r, 'Spending spikes'), '1 day(s)'); // 30000 > 2 x 5500
      expect(metric(r, 'Longest gap'), '9 day(s)'); // Aug 24 -> Sep 2
      expect(r.section.insight,
          'Your spending varies considerably across periods, mainly because of larger irregular expenses.');
      expect(r.section.bars.map((b) => b.value), [8000, 36000]);
      expect(r.section.bars2.first.label, 'Shopping');
      expect(r.section.watch.any((w) => w.contains('68% of total spend')), isTrue);
      expect(r.recommendations.any((x) => x.contains('₹10000')), isTrue); // 30000 / 3 months
    });

    test('steady data is reported as steady', () {
      final r = run(steady());
      expect(metric(r, 'Monthly variation'), '0%');
      expect(r.section.insight, 'Your monthly spending has been fairly steady (0% variation).');
      expect(r.section.strengths, contains('Few unusually large transactions'));
    });

    test('savings transfers are ignored', () {
      final r = run([...steady(), _e('t', '2026-09-28', 50000, 'Savings', true)]);
      expect(metric(r, 'Monthly variation'), '0%');
    });

    test('insufficient history: one month, or too few transactions', () {
      final oneMonth = run([
        for (var i = 1; i <= 8; i++) _e('m$i', '2026-09-0$i', 1000, 'Food'),
      ]);
      expect(oneMonth.section.notEnoughData, isTrue);
      expect(oneMonth.section.message, contains('2 or more months'));

      final few = run(volatile.take(7).toList());
      expect(few.section.notEnoughData, isTrue);
    });
  });

  // ───────────────────────── Loan & EMI Focused ─────────────────────────

  group('Loan & EMI Focused', () {
    const le = 'Loan & EMI Focused';
    AnalysisResult run(List<Expense> ex, {double income = 50000, List<String> fixed = const []}) =>
        _run(ex,
            persona: le,
            onboarding: OnboardingRecord(monthlyIncome: income, persona: le, fixedExpenses: fixed));
    String metric(AnalysisResult r, String label) =>
        r.section.metrics.firstWhere((m) => m.label == label).value;

    /// Per month: Home Loan EMI 18000 + Car EMI 6000 (both flagged fixed),
    /// Rent 12000 (fixed), Groceries 5000, Shopping 4000, Entertainment 2000.
    List<Expense> month(String m) => [
          _e('$m-hl', '$m-05', 18000, 'Home Loan EMI', true),
          _e('$m-car', '$m-07', 6000, 'Car EMI', true),
          _e('$m-rent', '$m-01', 12000, 'Rent', true),
          _e('$m-gro', '$m-03', 5000, 'Groceries'),
          _e('$m-shp', '$m-12', 4000, 'Shopping'),
          _e('$m-ent', '$m-15', 2000, 'Entertainment'),
        ];
    List<Expense> data() => [...month('2026-08'), ...month('2026-09')];

    test('EMI data: ratios, commitments counted once, disposable income', () {
      final r = run(data());
      expect(r.section.notEnoughData, isFalse);
      expect(metric(r, 'EMI / loan payments'), '₹48000'); // 2 x 24000
      expect(r.section.metrics.first.hint, '4 payment(s)');
      expect(metric(r, 'EMI-to-income'), '32%'); // 48000 / 150000
      expect(metric(r, 'Share of spending'), '51%'); // 48000 / 94000
      expect(metric(r, 'Fixed commitments'), '₹72000'); // EMIs 48000 + rent 24000, no double count
      expect(metric(r, 'Disposable income'), '₹78000'); // 150000 - 72000
      expect(metric(r, 'Non-essential spending'), '₹12000'); // shopping + entertainment
      expect(r.section.insight,
          'Loan and EMI payments take a moderate share (32%) of your income.');
      expect(r.section.bars.map((b) => b.value), [48000, 24000, 22000]);
      expect(r.section.bars2.map((b) => b.value), [24000, 24000]);
    });

    test('heavy EMI load: significant wording and negative disposable income', () {
      final r = run(data(), income: 20000); // 60000 over 3 months
      expect(metric(r, 'EMI-to-income'), '80%');
      expect(metric(r, 'Disposable income'), '-₹12000');
      expect(r.section.insight,
          'A significant portion of your income is committed to loan and EMI payments.');
      expect(r.section.watch.any((w) => w.contains('exceed income by ₹12000')), isTrue);
    });

    test('no EMI transactions: no fake EMI values', () {
      final r = run([
        for (final m in ['2026-08', '2026-09']) ...[
          _e('$m-rent', '$m-01', 12000, 'Rent', true),
          _e('$m-ins', '$m-04', 3000, 'Insurance Premium'), // "Premium" is not an EMI
          _e('$m-gro', '$m-08', 5000, 'Groceries'),
        ],
      ]);
      expect(r.section.notEnoughData, isTrue);
      expect(r.section.message, contains('No EMI or loan transactions'));
      expect(r.section.metrics, isEmpty);
    });

    test('no EMI transactions but EMIs declared in onboarding: says so', () {
      final r = run([
        for (final m in ['2026-08', '2026-09']) ...[
          _e('$m-rent', '$m-01', 12000, 'Rent', true),
          _e('$m-gro', '$m-08', 5000, 'Groceries'),
          _e('$m-shp', '$m-10', 2000, 'Shopping'),
        ],
      ], fixed: ['Home Loan EMI']);
      expect(r.section.message, contains('Home Loan EMI'));
    });

    test('zero income: EMI figures shown, income ratios say not enough data', () {
      final r = run(data(), income: 0);
      expect(metric(r, 'EMI / loan payments'), '₹48000');
      expect(metric(r, 'EMI-to-income'), 'Not enough data yet');
      expect(metric(r, 'Disposable income'), 'Not enough data yet');
      expect(r.section.insight, 'EMI payments are 51% of your recorded spending.');
    });
  });

  // ───────────────────────── Goal-Oriented Saver ─────────────────────────

  group('Goal-Oriented Saver', () {
    const go = 'Goal-Oriented Saver';
    AnalysisResult run(List<Expense> ex,
            {double income = 50000, String? goal = 'Buy a Home', double target = 30000}) =>
        _run(ex,
            persona: go,
            savingsGoal: target,
            onboarding: OnboardingRecord(monthlyIncome: income, persona: go, financialGoal: goal));
    String metric(AnalysisResult r, String label) =>
        r.section.metrics.firstWhere((m) => m.label == label).value;

    /// Per month: spending 25000 (Rent 15000 fixed, Groceries 5000,
    /// Shopping 5000) + a 5000 Savings transfer. Income 50000 -> saved 25000.
    List<Expense> month(String m) => [
          _e('$m-rent', '$m-01', 15000, 'Rent', true),
          _e('$m-gro', '$m-03', 5000, 'Groceries'),
          _e('$m-shp', '$m-12', 5000, 'Shopping'),
          _e('$m-sav', '$m-15', 5000, 'Savings', true),
        ];
    List<Expense> data() => [...month('2026-08'), ...month('2026-09')];

    test('close to target: progress, remaining, logged savings', () {
      final r = run(data());
      expect(r.section.notEnoughData, isFalse);
      expect(metric(r, 'Goal'), 'Buy a Home');
      expect(metric(r, 'Monthly target'), '₹30000');
      expect(metric(r, 'Current monthly savings'), '₹25000'); // 50000 - 25000, transfers not spent
      expect(metric(r, 'Goal progress'), '83%');
      expect(metric(r, 'Remaining each month'), '₹5000');
      expect(metric(r, 'Logged savings & investments'), '₹5000');
      expect(r.section.insight, 'You are close to your monthly savings target (83%).');
      expect(r.section.bars.map((b) => b.value), [25000, 25000]);
      expect(r.section.bars2.map((b) => b.value), [25000, 30000]);
      expect(r.section.watch.any((w) => w.contains('₹5000 short')), isTrue);
      expect(r.recommendations.any((x) => x.contains('"Buy a Home"')), isTrue);
      expect(r.recommendations.any((x) => x.contains('Rent is your largest spending category')), isTrue);
      expect(r.recommendations.any((x) => x.contains('Savings is your')), isFalse);
    });

    test('target exceeded: aligned insight, progress capped at 100%', () {
      final r = run(data(), target: 20000);
      expect(r.section.insight, 'Your current saving behaviour is aligned with your financial goal.');
      expect(metric(r, 'Goal progress'), '100%');
      expect(metric(r, 'Remaining each month'), '₹0');
      expect(r.section.strengths, contains('Target met in every month analysed'));
    });

    test('well below target', () {
      final r = run(data(), target: 60000);
      expect(metric(r, 'Goal progress'), '42%'); // 25000 / 60000
      expect(r.section.insight, 'You are currently saving 42% of your monthly target.');
      expect(metric(r, 'Remaining each month'), '₹35000');
    });

    test('spending above income: no progress claimed', () {
      final r = run(data(), income: 10000);
      expect(metric(r, 'Current monthly savings'), '-₹15000');
      expect(metric(r, 'Goal progress'), '0%');
      expect(r.section.insight,
          'Spending has been at or above income, so nothing is being set aside towards your goal yet.');
      expect(r.section.watch, contains('Spending exceeded income in at least one month'));
    });

    test('no goal / no target / no income: no fake goal progress', () {
      final noGoal = run(data(), goal: null);
      expect(noGoal.section.notEnoughData, isTrue);
      expect(noGoal.section.message, contains('No financial goal found'));

      final noTarget = run(data(), target: 0);
      expect(noTarget.section.notEnoughData, isTrue);
      expect(noTarget.section.message, contains('no monthly savings target'));

      final noIncome = run(data(), income: 0);
      expect(noIncome.section.notEnoughData, isTrue);
      expect(noIncome.section.message, contains('income'));
    });
  });

  test('all six personas have an analysis; unknown values are handled', () {
    for (final p in PersonaAnalysisService.personas) {
      expect(PersonaAnalysisService.hasAnalysis(p), isTrue, reason: p);
    }
    expect(PersonaAnalysisService.hasAnalysis('Something Else'), isFalse);
    expect(PersonaAnalysisService.hasAnalysis(null), isFalse);
    final r = _run(_month('2026-09', 20000), persona: 'Something Else');
    expect(r.persona, isNull);
    expect(r.section.message, contains('No persona found'));
  });
}
