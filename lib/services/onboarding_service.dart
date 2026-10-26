import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:finora/models/onboarding_data.dart';
import 'package:finora/models/onboarding_record.dart';

/// All Supabase access for the `onboarding` table.
///
/// Every onboarding answer (profession, income_type, monthly_income,
/// fixed_expenses, spending_habit, financial_goal, saving_percentage,
/// budget_discipline, expense_tracking_frequency, ai_budget_assistant,
/// persona, onboarding_completed) is saved here — never on `profiles`.
class OnboardingService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<OnboardingRecord?> getOnboarding(String userId) async {
    try {
      final row = await _client
          .from('onboarding')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      return row == null ? null : OnboardingRecord.fromMap(row);
    } catch (e) {
      debugPrint('OnboardingService.getOnboarding error: $e');
      return null;
    }
  }

  /// Changes only the persona on the user's existing onboarding row, so they
  /// can switch persona after login without redoing the wizard.
  /// Returns null on success, or an error message. Verifies a row was
  /// really changed (Supabase returns no error when RLS or a missing row
  /// makes an update match 0 rows).
  static Future<String?> updatePersona(String userId, String persona) async {
    try {
      final rows = await _client
          .from('onboarding')
          .update({'persona': persona})
          .eq('user_id', userId)
          .select('persona');
      if ((rows as List).isEmpty) {
        return 'No onboarding record was updated (blocked by database permissions or missing row).';
      }
      if (rows.first['persona'] != persona) return 'Database kept the old persona.';
      debugPrint('✅ Persona changed for $userId — $persona');
      return null;
    } catch (e) {
      debugPrint('❌ OnboardingService.updatePersona error: $e');
      return 'Could not save: $e';
    }
  }

  /// Saves the wizard's answers for [userId]. Uses an explicit
  /// select-then-insert/update instead of `upsert(onConflict: 'user_id')`
  /// so this works regardless of whether the table has a unique constraint
  /// on `user_id` — we're not allowed to change the schema to add one.
  static Future<bool> saveOnboarding(String userId, OnboardingData data) async {
    try {
      final existing = await _client
          .from('onboarding')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      final payload = data.toOnboardingMap();

      // Safety net: `onboarding.saving_percentage` is a numeric column.
      // `toOnboardingMap()` already converts the UI's bucket string
      // ('0–10%', ...) to a number, but guard here too so this table is
      // never sent text for that column no matter how the payload was
      // built.
      final rawSaving = payload['saving_percentage'];
      if (rawSaving != null && rawSaving is! num) {
        payload['saving_percentage'] = num.tryParse(rawSaving.toString());
      }

      // Safety net: `onboarding.fixed_expenses` is a JSONB column that
      // expects a JSON OBJECT (e.g. {"Rent": true}). Postgres throws
      // "cannot call jsonb_object_keys on an array" if we ever send a
      // JSON array instead. `toOnboardingMap()` already builds an object,
      // but guard here too in case a List ever slips through.
      final rawFixedExpenses = payload['fixed_expenses'];
      if (rawFixedExpenses is List) {
        payload['fixed_expenses'] = {
          for (final e in rawFixedExpenses) e.toString(): true,
        };
      }

      if (existing == null) {
        await _client.from('onboarding').insert({
          'user_id': userId,
          ...payload,
        });
      } else {
        await _client
            .from('onboarding')
            .update(payload)
            .eq('user_id', userId);
      }

      debugPrint('✅ Onboarding saved for $userId — persona: ${payload['persona']}');
      return true;
    } catch (e) {
      debugPrint('❌ OnboardingService.saveOnboarding error: $e');
      return false;
    }
  }
}
