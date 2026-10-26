import 'package:flutter/foundation.dart';
import 'package:finora/models/persona_dataset_item.dart';
import 'package:finora/services/persona_dataset_service.dart';

/// Holds the current user's detected persona and the matching
/// `persona_dataset` rows in memory for the rest of the session.
///
/// Nothing here talks to Supabase directly — all queries live in
/// [PersonaDatasetService]. No ML/analysis happens here either; this is
/// purely "fetch once after login, keep in memory for later".
class PersonaDatasetProvider extends ChangeNotifier {
  String? _persona;
  List<PersonaDatasetItem> _dataset = [];
  bool _loading = false;
  String? _error;

  String? get persona => _persona;
  List<PersonaDatasetItem> get dataset => List.unmodifiable(_dataset);
  bool get loading => _loading;
  String? get error => _error;
  bool get hasData => _dataset.isNotEmpty;

  /// Steps 2–4: given a persona already read from the onboarding data,
  /// fetch every matching `persona_dataset` row and keep it in memory.
  Future<void> loadForPersona(String persona) async {
    if (persona.isEmpty) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _persona = persona;
      _dataset = await PersonaDatasetService.getDatasetForPersona(persona);
    } catch (e) {
      _error = 'Could not load persona dataset';
      _dataset = [];
    }

    _loading = false;
    notifyListeners();
  }

  /// Steps 1–4 in one call: reads the user's persona from their onboarding
  /// data, then fetches the matching dataset. Use this when the caller
  /// hasn't already loaded the profile (e.g. right after sign-in).
  Future<void> loadForUser(String userId) async {
    _loading = true;
    _error = null;
    notifyListeners();

    final persona = await PersonaDatasetService.getUserPersona(userId);
    if (persona == null) {
      _loading = false;
      _error = 'No persona found for this user';
      notifyListeners();
      return;
    }

    await loadForPersona(persona);
  }

  /// Clears the in-memory dataset (e.g. on sign-out).
  void clear() {
    _persona = null;
    _dataset = [];
    _error = null;
    notifyListeners();
  }
}
