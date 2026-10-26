# Finora — Flutter

A personal finance tracker converted from the React/TypeScript web app to Flutter.

## Features

- 🔐 Supabase Auth (email/password)
- 📊 Dashboard with live clock, spending stats & smart insights
- 💸 Expenses — add, delete, search with category/mood/payment mode tags
- 📅 Calendar view with per-day expense drill-down
- 🤖 AI Predictions — actual vs predicted charts, monthly bar chart, category pie chart
- 👤 Profile — budget limits, savings goal progress bar, logout

## Project Structure

```
lib/
├── main.dart              # App entry point + Supabase init
├── router.dart            # go_router navigation with auth guard
├── models/
│   └── expense.dart       # Expense, UserData, BudgetLimits
├── services/
│   ├── auth_provider.dart # ChangeNotifier wrapping Supabase auth
│   └── supabase_service.dart  # All DB calls
├── utils/
│   ├── theme.dart         # Dark theme, colors, constants
│   └── finance_utils.dart # Ported finance calculation logic
├── widgets/
│   ├── glass_card.dart    # Reusable frosted-glass card
│   ├── gradient_button.dart
│   └── bottom_nav.dart    # 5-tab bottom navigation
└── screens/
    ├── login_screen.dart
    ├── signup_screen.dart
    ├── onboarding_screen.dart
    ├── dashboard_screen.dart
    ├── expenses_screen.dart
    ├── calendar_screen.dart
    ├── predictions_screen.dart
    └── profile_screen.dart
```

## Setup

### 1. Install Flutter
https://docs.flutter.dev/get-started/install

### 2. Add Supabase credentials

Open `lib/main.dart` and replace:
```dart
const _supabaseUrl = 'YOUR_SUPABASE_URL';
const _supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
```

Find these in your Supabase dashboard → Settings → API.

### 3. Run the app

```bash
flutter pub get
flutter run
```

## Dependencies

| Package | Purpose |
|---|---|
| `supabase_flutter` | Auth + database |
| `go_router` | Navigation |
| `provider` | State management |
| `fl_chart` | Charts (line, bar, pie) |
| `google_fonts` | Inter + Space Grotesk fonts |
| `flutter_animate` | Animations |
| `intl` | Date formatting |

## Database

- `profiles` — full_name, email, phone_number, profile_image
  (`id` = the Supabase auth user id). Account info only — no financial or
  onboarding data lives here.
- `onboarding` — user_id, profession, income_type, monthly_income,
  fixed_expenses, spending_habit, financial_goal, saving_percentage,
  budget_discipline, expense_tracking_frequency, ai_budget_assistant,
  persona, onboarding_completed. Everything the onboarding wizard collects,
  plus the computed persona, is saved here — never on `profiles`.
- `persona_dataset` — the imported reference dataset (1500 rows across 6
  personas), matched against `onboarding.persona` after onboarding.
- `expenses` — date, amount, category, mood, payment_mode, is_subscription
- `budget_limits` — daily_limit, weekly_limit, savings_goal

Schema reference (nothing to run): `supabase/onboarding_migration.sql`.

### Services

- `ProfileService` (`lib/services/profile_service.dart`) — all reads/writes
  to `profiles`.
- `OnboardingService` (`lib/services/onboarding_service.dart`) — all
  reads/writes to `onboarding`.
- `PersonaDatasetService` (`lib/services/persona_dataset_service.dart`) —
  reads the user's persona from `onboarding` and fetches matching
  `persona_dataset` rows.
- `SupabaseService` (`lib/services/supabase_service.dart`) — auth, expenses,
  budget limits.
