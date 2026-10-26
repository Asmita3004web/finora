import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:finora/models/persona_dataset_item.dart';

/// All Supabase access related to reading a user's onboarding persona and
/// pulling the matching rows from `persona_dataset`.
///
/// This is intentionally the only place in the app that talks to the
/// `persona_dataset` table (or reads the `persona` column), per the
/// "queries stay inside services" rule.
class PersonaDatasetService {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Step 1 + 2: fetch the signed-in user's onboarding row and read the
  /// persona that was assigned during onboarding.
  ///
  /// Onboarding answers (including `persona`) live on the `onboarding`
  /// table, keyed by `user_id` — never on `profiles`. Returns null if the
  /// user hasn't completed onboarding yet or no persona was ever recorded.
  static Future<String?> getUserPersona(String userId) async {
    try {
      final row = await _client
          .from('onboarding')
          .select('persona')
          .eq('user_id', userId)
          .maybeSingle();
      final persona = row?['persona'] as String?;
      return (persona == null || persona.isEmpty) ? null : persona;
    } catch (e) {
      debugPrint('getUserPersona error: $e');
      return null;
    }
  }

  /// Step 3: fetch every row from `persona_dataset` matching the given
  /// persona — equivalent to:
  ///   SELECT * FROM persona_dataset WHERE persona = :persona
  static Future<List<PersonaDatasetItem>> getDatasetForPersona(
    String persona,
  ) async {
    try {
      final rows = await _client
          .from('persona_dataset')
          .select()
          .eq('persona', persona);
      return (rows as List)
          .map((row) => PersonaDatasetItem.fromMap(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('getDatasetForPersona error: $e');
      return [];
    }
  }
}
