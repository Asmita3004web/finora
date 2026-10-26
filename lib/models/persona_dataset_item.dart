/// A single row from the `persona_dataset` table.
///
/// The dataset schema is intentionally treated as opaque here — we don't
/// know (and per the task, must not change) its exact columns beyond
/// `persona`. Every column Supabase returns is kept in [raw] so future
/// analysis / ML work can read whatever fields it needs without another
/// migration to this model.
class PersonaDatasetItem {
  final String persona;
  final Map<String, dynamic> raw;

  PersonaDatasetItem({required this.persona, required this.raw});

  factory PersonaDatasetItem.fromMap(Map<String, dynamic> map) {
    return PersonaDatasetItem(
      persona: map['persona'] as String? ?? '',
      raw: map,
    );
  }

  /// Convenience getter for any column by name, without needing to know
  /// the full schema up front.
  dynamic operator [](String column) => raw[column];

  @override
  String toString() => 'PersonaDatasetItem(persona: $persona, raw: $raw)';
}
