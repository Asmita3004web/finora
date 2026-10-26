import 'package:finora/models/expense.dart';
import 'package:finora/models/onboarding_record.dart';

class FinanceUtils {
  static String toDateKey(DateTime date) {
    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static double getMonthlySpending(List<Expense> expenses, {int? month}) {
    final now = DateTime.now();
    final m = month ?? now.month;
    final y = now.year;
    return expenses
        .where((e) {
          final d = DateTime.tryParse(e.date);
          return d != null && d.month == m && d.year == y;
        })
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  static double getTodaySpending(List<Expense> expenses) {
    final today = toDateKey(DateTime.now());
    return expenses
        .where((e) => e.date == today)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  static double getWeekSpending(List<Expense> expenses) {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    return expenses
        .where((e) {
          final d = DateTime.tryParse(e.date);
          return d != null && d.isAfter(weekAgo);
        })
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  static double getYearlySpending(List<Expense> expenses) {
    final y = DateTime.now().year;
    return expenses
        .where((e) => DateTime.tryParse(e.date)?.year == y)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  static Map<String, double> getCategoryTotals(List<Expense> expenses) {
    final Map<String, double> totals = {};
    for (final e in expenses) {
      totals[e.category] = (totals[e.category] ?? 0) + e.amount;
    }
    return totals;
  }

  static double predictMonthlySpending(List<Expense> expenses) {
    if (expenses.length < 7) return 0;

    final Map<String, double> monthly = {};
    for (final e in expenses) {
      final key = e.date.substring(0, 7);
      monthly[key] = (monthly[key] ?? 0) + e.amount;
    }

    final values = monthly.values.toList();
    if (values.isEmpty) return 0;

    // Simple Moving Average
    final sma = values.reduce((a, b) => a + b) / values.length;

    // Weighted Moving Average
    double wma = 0, wTotal = 0;
    for (int i = 0; i < values.length; i++) {
      final w = (i + 1).toDouble();
      wma += values[i] * w;
      wTotal += w;
    }
    wma /= wTotal;

    // Exponential smoothing
    double ema = values[0];
    const alpha = 0.3;
    for (final v in values) {
      ema = alpha * v + (1 - alpha) * ema;
    }

    return ((sma + wma + ema) / 3).roundToDouble();
  }

  static List<Map<String, dynamic>> getDailySpendingData(List<Expense> expenses) {
    final Map<String, double> daily = {};
    for (final e in expenses) {
      daily[e.date] = (daily[e.date] ?? 0) + e.amount;
    }
    final sorted = daily.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return sorted.map((e) => {'date': e.key, 'amount': e.value}).toList();
  }

  static List<Map<String, dynamic>> getPredictedDailyData(List<Expense> expenses) {
    final daily = getDailySpendingData(expenses);
    if (daily.length < 3) return [];

    final List<Map<String, dynamic>> result = [];
    double ema = (daily[0]['amount'] as double);
    const alpha = 0.3;

    for (final d in daily) {
      result.add({'date': d['date'], 'predicted': ema.roundToDouble()});
      ema = alpha * (d['amount'] as double) + (1 - alpha) * ema;
    }

    // Predict next 30 days
    final lastDate = DateTime.tryParse(daily.last['date'] as String) ?? DateTime.now();
    for (int i = 1; i <= 30; i++) {
      final nextDate = lastDate.add(Duration(days: i));
      result.add({
        'date': toDateKey(nextDate),
        'predicted': ema.roundToDouble(),
      });
    }

    return result;
  }

  static List<String> getSmartInsights(List<Expense> expenses, OnboardingRecord user) {
    final insights = <String>[];
    final cats = getCategoryTotals(expenses);
    final total = cats.values.fold(0.0, (a, b) => a + b);

    if (total == 0) return ['Start logging expenses to get smart insights!'];

    final topCat = cats.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (topCat.isNotEmpty) {
      final pct = ((topCat.first.value / total) * 100).round();
      insights.add('${topCat.first.key} takes $pct% of your spending');
    }

    if (user.isStudent && user.monthlyIncome > 0) {
      final safeDailyLimit = (user.monthlyIncome / 30).round();
      insights.add('Keep daily spending under ₹$safeDailyLimit to stay on budget');
    }

    final weekTotal = getWeekSpending(expenses);
    final avgWeekly = total / (expenses.length / 7).ceil().clamp(1, 9999);
    if (weekTotal > avgWeekly * 1.2) {
      final overPct = (((weekTotal - avgWeekly) / avgWeekly) * 100).round();
      insights.add("This week's spending is $overPct% above average");
    }

    final savings = user.monthlyIncome - getMonthlySpending(expenses);
    if (savings > 0) {
      insights.add('You can save ₹${savings.toStringAsFixed(0)} this month!');
    } else {
      insights.add('⚠️ You\'ve overspent by ₹${savings.abs().toStringAsFixed(0)} this month');
    }

    return insights;
  }

  static List<String> getSavingsTips(List<Expense> expenses, OnboardingRecord user) {
    final tips = <String>[];
    final cats = getCategoryTotals(expenses);
    final total = cats.values.fold(0.0, (a, b) => a + b);
    if (total == 0) return ['Start tracking expenses to get saving tips!'];

    final sorted = cats.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.isNotEmpty) {
      final pct = ((sorted.first.value / total) * 100).round();
      if (pct > 28) {
        final save = (sorted.first.value * 0.15).round();
        tips.add('${sorted.first.key} takes ₹${sorted.first.value.toStringAsFixed(0)} ($pct%) — cutting 15% saves ≈₹$save');
      }
    }

    final subs = expenses.where((e) => e.isSubscription).toList();
    if (subs.isNotEmpty) {
      final subTotal = subs.fold(0.0, (s, e) => s + e.amount);
      tips.add('Subscriptions cost ₹${subTotal.toStringAsFixed(0)} — cancel unused ones');
    }

    if ((cats['Shopping'] ?? 0) > total * 0.2) {
      tips.add('Shopping at ₹${cats['Shopping']!.toStringAsFixed(0)} — set a weekly cap');
    }
    if ((cats['Food'] ?? 0) > total * 0.35) {
      final pct = ((cats['Food']! / total) * 100).round();
      tips.add('Food is $pct% of spending — cook more to cut this fast');
    }

    if (user.isStudent) {
      final safeDaily = (user.monthlyIncome / 30).round().clamp(0, 99999);
      tips.add('Target ₹$safeDaily/day flexible spend and use student discounts');
    }

    if (tips.isEmpty) tips.add("You're doing great! Keep tracking to find more savings.");
    return tips;
  }

  static Map<String, double> getMonthlyTotals(List<Expense> expenses) {
    final Map<String, double> monthly = {};
    for (final e in expenses) {
      final key = e.date.substring(0, 7);
      monthly[key] = (monthly[key] ?? 0) + e.amount;
    }
    return Map.fromEntries(monthly.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }
}
