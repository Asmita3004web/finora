import 'package:finora/models/expense.dart';
import 'package:finora/models/onboarding_record.dart';
import 'package:finora/models/profile.dart';
import 'package:finora/utils/finance_utils.dart';
import 'package:finora/services/ai_insights_service.dart';

/// Snapshot of everything the assistant is allowed to reason about, built
/// once per chat session from data the app already loaded (never fetched
/// or fabricated by the chat service itself). Nothing in here is invented
/// — if a field is missing/zero, the assistant says so instead of guessing.
class AiChatContext {
  final Profile profile;
  final OnboardingRecord onboarding;
  final List<Expense> expenses;
  final BudgetLimits limits;
  final int safeLockWarningCount;
  final bool safeLockActive;

  final double monthlyBudget;
  final double monthlySpent;
  final double predictedSpend;
  final double todaySpent;
  final double weekSpent;
  final Map<String, double> categoryTotals;

  AiChatContext({
    required this.profile,
    required this.onboarding,
    required this.expenses,
    required this.limits,
    required this.safeLockWarningCount,
    required this.safeLockActive,
  })  : monthlyBudget = AiInsightsService.effectiveMonthlyBudget(
          savingsGoal: limits.savingsGoal,
          monthlyIncome: onboarding.monthlyIncome,
        ),
        monthlySpent = FinanceUtils.getMonthlySpending(expenses),
        predictedSpend = _predicted(expenses),
        todaySpent = FinanceUtils.getTodaySpending(expenses),
        weekSpent = FinanceUtils.getWeekSpending(expenses),
        categoryTotals = FinanceUtils.getCategoryTotals(expenses);

  static double _predicted(List<Expense> expenses) {
    final p = FinanceUtils.predictMonthlySpending(expenses);
    return p > 0 ? p : FinanceUtils.getMonthlySpending(expenses);
  }

  double get remainingBudget => (monthlyBudget - monthlySpent);

  bool get hasIncomeData => onboarding.monthlyIncome > 0;
  bool get hasExpenseData => expenses.isNotEmpty;
  bool get hasBudgetData => monthlyBudget > 0;
}

/// A reply from the assistant: the message text plus optional tappable
/// follow-up chips (e.g. "View Budget", "Reduce Expenses").
class AiChatReply {
  final String text;
  final List<String> suggestedActions;
  const AiChatReply(this.text, {this.suggestedActions = const []});
}

/// Abstract chat backend. Swap `DemoAIChatService` for a real API-backed
/// implementation later — the UI only ever talks to this interface.
abstract class AIChatService {
  Future<AiChatReply> ask(String message, AiChatContext ctx);
}

/// Rule-based fallback assistant used until a real AI API/backend is
/// wired up. Every answer is derived from [AiChatContext] — real
/// onboarding/expense/budget/SafeLock data — never invented. This is a
/// clearly-marked demo implementation (see `AiAssistantScreen`, which
/// labels the assistant as running in demo/rule-based mode), not a
/// disguised stand-in for a real model.
class DemoAIChatService implements AIChatService {
  static const _personaTones = {
    'Consistent Saver': 'maintaining your consistency and long-term savings habits',
    'Balanced Planner': 'balanced spending and thoughtful planning',
    'Lifestyle Spender': 'keeping discretionary spending in check',
    'Irregular Spender': 'spotting unpredictable spending patterns',
    'Loan & EMI Focused': 'staying on top of EMI obligations and debt-aware budgeting',
    'Goal-Oriented Saver': 'your progress toward your financial goals',
  };

  @override
  Future<AiChatReply> ask(String message, AiChatContext ctx) async {
    final text = message.toLowerCase().trim();

    if (_mentions(text, ['safelock', 'safe lock'])) {
      return _safeLockReply(ctx);
    }
    if (_mentions(text, ['invest', 'stock', 'mutual fund', 'sip', 'crypto'])) {
      return _investmentReply(ctx);
    }
    if (_mentions(text, ['afford', 'can i buy', 'can i spend']) || _extractAmount(text) != null) {
      return _affordabilityReply(text, ctx);
    }
    if (_mentions(text, ['how much can i spend today', 'spend today', 'today'])) {
      return _todayAllowanceReply(ctx);
    }
    if (_mentions(text, ['why', 'overspend']) || _mentions(text, ['where']) && _mentions(text, ['spend', 'overspend'])) {
      return _overspendingReply(ctx);
    }
    if (_mentions(text, ['save more', 'how can i save', 'saving tips', 'save'])) {
      return _savingsReply(ctx);
    }
    if (_mentions(text, ['show my budget', 'budget'])) {
      return _budgetSummaryReply(ctx);
    }
    if (_mentions(text, ['analyze', 'analyse', 'analysis'])) {
      return _analysisReply(ctx);
    }

    return _fallbackReply(ctx);
  }

  bool _mentions(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  double? _extractAmount(String text) {
    final match = RegExp(r'(\d[\d,]*)').firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(1)!.replaceAll(',', ''));
  }

  String _personaPrefix(AiChatContext ctx) {
    final persona = ctx.onboarding.persona;
    if (persona == null || !_personaTones.containsKey(persona)) return '';
    return 'As a ${persona.toLowerCase()}, I\'m keeping an eye on ${_personaTones[persona]}. ';
  }

  AiChatReply _safeLockReply(AiChatContext ctx) {
    if (ctx.safeLockActive) {
      return const AiChatReply(
        '🔒 SafeLock Active\n\nYour spending has crossed the current safety '
        'threshold. Let\'s review your remaining budget before making another '
        'discretionary purchase.',
        suggestedActions: ['View Budget', 'Reduce Expenses'],
      );
    }
    if (ctx.safeLockWarningCount > 0) {
      return AiChatReply(
        'SafeLock is active but not locked yet — you\'re at '
        '${ctx.safeLockWarningCount}/3 warnings this month. Staying under your '
        'budget will keep it that way.',
        suggestedActions: const ['View Budget'],
      );
    }
    return const AiChatReply(
      '🔒 SafeLock: Protected. No warnings on your account right now — '
      'you\'re within your budget.',
    );
  }

  AiChatReply _investmentReply(AiChatContext ctx) {
    // Educational only — never presented as guaranteed advice.
    return const AiChatReply(
      'I can share general educational information, but I\'m not a '
      'licensed financial advisor, so please treat this as a starting '
      'point rather than guaranteed advice. Generally: build an emergency '
      'fund first, invest only money you won\'t need short-term, and match '
      'risk (stocks/mutual funds/SIPs/crypto) to your goals and timeline. '
      'For a plan tailored to your situation, it\'s worth speaking with a '
      'registered financial advisor.',
      suggestedActions: ['Show my budget'],
    );
  }

  AiChatReply _affordabilityReply(String text, AiChatContext ctx) {
    final amount = _extractAmount(text);
    if (amount == null) {
      return const AiChatReply(
        'Sure — how much are you thinking of spending, and on what? '
        'Send me an amount (e.g. "Can I spend ₹2000 on shopping?") and '
        'I\'ll check it against your budget.',
      );
    }
    if (!ctx.hasBudgetData) {
      return const AiChatReply(
        'I don\'t have a monthly budget set for your account yet, so I '
        'can\'t give you a precise answer — set one from your budget/goal '
        'settings and I\'ll be able to compare purchases against it.',
        suggestedActions: ['View Budget'],
      );
    }

    final remaining = ctx.remainingBudget;
    final wouldExceed = amount > remaining;
    final prefix = _personaPrefix(ctx);

    if (wouldExceed) {
      final over = amount - remaining;
      return AiChatReply(
        '${prefix}Based on your current budget and spending so far this '
        'month (₹${ctx.monthlySpent.toStringAsFixed(0)} of '
        '₹${ctx.monthlyBudget.toStringAsFixed(0)}), you have about '
        '₹${remaining.clamp(0, double.infinity).toStringAsFixed(0)} left. '
        'Spending ₹${amount.toStringAsFixed(0)} would go about '
        '₹${over.toStringAsFixed(0)} over that — I\'d recommend keeping this '
        'purchase below ₹${remaining.clamp(0, double.infinity).toStringAsFixed(0)}.',
        suggestedActions: const ['View Budget', 'Reduce Expenses'],
      );
    }

    return AiChatReply(
      '${prefix}Yes — you have about '
      '₹${remaining.toStringAsFixed(0)} left in your monthly budget, so '
      '₹${amount.toStringAsFixed(0)} fits comfortably. Just keep an eye on '
      'the rest of the month if you have other planned expenses.',
      suggestedActions: const ['View Budget'],
    );
  }

  AiChatReply _todayAllowanceReply(AiChatContext ctx) {
    if (!ctx.hasBudgetData) {
      return const AiChatReply(
        'I don\'t have enough budget data yet to calculate a safe daily '
        'amount — once you set a monthly budget I can work this out '
        'precisely.',
        suggestedActions: ['View Budget'],
      );
    }
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysLeft = (daysInMonth - now.day + 1).clamp(1, daysInMonth);
    final remaining = ctx.remainingBudget.clamp(0, double.infinity);
    final dailyAllowance = remaining / daysLeft;

    return AiChatReply(
      'You\'ve spent ₹${ctx.todaySpent.toStringAsFixed(0)} today. With '
      '₹${remaining.toStringAsFixed(0)} left in your monthly budget across '
      '$daysLeft day${daysLeft == 1 ? '' : 's'} remaining, a safe amount to '
      'spend today is around ₹${dailyAllowance.toStringAsFixed(0)}.',
      suggestedActions: const ['View Budget'],
    );
  }

  AiChatReply _overspendingReply(AiChatContext ctx) {
    if (!ctx.hasExpenseData) {
      return const AiChatReply(
        'I don\'t see any logged transactions yet, so I can\'t point to a '
        'specific category — start logging expenses and I\'ll be able to '
        'analyze your patterns.',
        suggestedActions: ['Show my budget'],
      );
    }
    final insights = FinanceUtils.getSmartInsights(ctx.expenses, ctx.onboarding);
    final sorted = ctx.categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.isNotEmpty ? sorted.first : null;

    final buffer = StringBuffer(_personaPrefix(ctx));
    if (top != null) {
      final total = ctx.categoryTotals.values.fold(0.0, (a, b) => a + b);
      final pct = total > 0 ? ((top.value / total) * 100).round() : 0;
      buffer.write(
        '${top.key} is your biggest category at ₹${top.value.toStringAsFixed(0)} '
        '($pct% of your logged spending). ',
      );
    }
    if (insights.isNotEmpty) buffer.write(insights.first);

    return AiChatReply(buffer.toString(), suggestedActions: const ['Reduce Expenses', 'View Budget']);
  }

  AiChatReply _savingsReply(AiChatContext ctx) {
    if (!ctx.hasExpenseData) {
      return const AiChatReply(
        'Start logging a few expenses and I\'ll be able to point out '
        'specific categories where you can cut back.',
      );
    }
    final tips = FinanceUtils.getSavingsTips(ctx.expenses, ctx.onboarding);
    final text = '${_personaPrefix(ctx)}${tips.take(2).join(' ')}';
    return AiChatReply(text, suggestedActions: const ['Reduce Expenses']);
  }

  AiChatReply _budgetSummaryReply(AiChatContext ctx) {
    if (!ctx.hasBudgetData) {
      return const AiChatReply(
        'You don\'t have a monthly budget set yet. Add one from your '
        'budget/goal settings and I\'ll track it for you here.',
      );
    }
    final remaining = ctx.remainingBudget;
    return AiChatReply(
      'Monthly Budget: ₹${ctx.monthlyBudget.toStringAsFixed(0)}\n'
      'Spent so far: ₹${ctx.monthlySpent.toStringAsFixed(0)}\n'
      'Predicted end-of-month: ₹${ctx.predictedSpend.toStringAsFixed(0)}\n'
      'Remaining: ₹${remaining.clamp(0, double.infinity).toStringAsFixed(0)}',
      suggestedActions: remaining < 0 ? const ['Reduce Expenses'] : const [],
    );
  }

  AiChatReply _analysisReply(AiChatContext ctx) {
    if (!ctx.hasExpenseData) {
      return const AiChatReply(
        'I don\'t have any transactions to analyze yet — add a few '
        'expenses and check back!',
      );
    }
    final sorted = ctx.categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top3 = sorted.take(3);
    final lines = top3
        .map((e) => '• ${e.key}: ₹${e.value.toStringAsFixed(0)}')
        .join('\n');
    return AiChatReply(
      '${_personaPrefix(ctx)}Here\'s your top spending this month:\n$lines',
      suggestedActions: const ['View Budget'],
    );
  }

  AiChatReply _fallbackReply(AiChatContext ctx) {
    return const AiChatReply(
      'I\'m running in demo mode right now, so my answers are rule-based '
      'rather than from a full AI model — but I can still work with your '
      'real numbers. Try asking things like "How much can I spend today?", '
      '"Where am I overspending?", or "Show my budget".',
    );
  }
}
