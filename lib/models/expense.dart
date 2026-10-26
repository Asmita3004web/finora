/// App-facing expense entry. Field names here (`date`, `paymentMode`,
/// `isSubscription`, `mood`) are unchanged — every screen/widget keeps
/// using this exact shape. Only [fromMap]/[toMap] — the boundary with
/// Supabase — changed, to point at the real `transactions` table instead
/// of a nonexistent `expenses` table (see SupabaseService for why).
class Expense {
  final String id;
  final String date;
  final double amount;
  final String category;
  final String mood;
  final String paymentMode;
  final bool isSubscription;

  Expense({
    required this.id,
    required this.date,
    required this.amount,
    required this.category,
    required this.mood,
    required this.paymentMode,
    required this.isSubscription,
  });

  /// Reads a row from `transactions`. Only `transaction_type = 'Expense'`
  /// rows are ever fetched by [SupabaseService.getExpenses] in the first
  /// place, so every row reaching this app is already an expense.
  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as String,
      date: map['transaction_date'] as String,
      // `amount` is a Postgres NUMERIC, which supabase_flutter can hand
      // back as num, double, or a numeric-looking String depending on
      // driver/version — parse defensively via toString() rather than a
      // direct cast so this never throws.
      amount: double.tryParse(map['amount'].toString()) ?? 0,
      category: map['category'] as String? ?? 'Other',
      // `transactions` has no `mood` column — this was always a
      // UI-only/local concept, so it just defaults here rather than
      // round-tripping through the database.
      mood: 'Neutral',
      paymentMode: map['payment_method'] as String? ?? 'UPI',
      isSubscription: map['is_fixed_expense'] as bool? ?? false,
    );
  }

  /// Writes to `transactions`. `transaction_type` is always hard-set to
  /// `'Expense'` here — this model/screen only ever creates expense rows,
  /// never income ones, so it can't accidentally mislabel a row.
  Map<String, dynamic> toMap(String userId) => {
    'user_id': userId,
    'transaction_date': date,
    'transaction_type': 'Expense',
    'category': category,
    'amount': amount,
    'payment_method': paymentMode,
    'is_fixed_expense': isSubscription,
    // `merchant` / `description` exist on `transactions` but nothing in
    // the current UI captures them as distinct, persisted values yet
    // (see ScanReceiptScreen/AddExpenseScreen) — sent as null rather than
    // omitted so every insert touches the same column set.
    'merchant': null,
    'description': null,
  };
}

// NOTE: The old `UserData` model (name/email/monthlyIncome/hostelRent/
// userType/persona/financialGoal all read off a single `profiles` row) has
// been removed. That shape never matched the real schema — `profiles` only
// holds account info (full_name, email, phone_number, profile_image) and
// every financial/onboarding answer (monthly_income, fixed_expenses,
// persona, financial_goal, ...) lives in the separate `onboarding` table.
// Screens now combine `Profile` (lib/models/profile.dart) with
// `OnboardingRecord` (lib/models/onboarding_record.dart) instead.

/// Local, per-device budget targets (daily/weekly/savings-goal).
///
/// There is no `budget_limits` table in the real database — see
/// SupabaseService.getBudgetLimits for why this is intentionally backed
/// by on-device storage instead of Supabase.
class BudgetLimits {
  final double daily;
  final double weekly;
  final double savingsGoal;

  BudgetLimits({
    this.daily = 1000,
    this.weekly = 5000,
    this.savingsGoal = 0,
  });

  factory BudgetLimits.fromMap(Map<String, dynamic> map) {
    return BudgetLimits(
      daily: double.tryParse(map['daily_limit'].toString()) ?? 1000,
      weekly: double.tryParse(map['weekly_limit'].toString()) ?? 5000,
      savingsGoal: double.tryParse(map['savings_goal'].toString()) ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'daily_limit': daily,
    'weekly_limit': weekly,
    'savings_goal': savingsGoal,
  };
}
