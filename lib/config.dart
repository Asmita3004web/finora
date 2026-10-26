/// ⚠️ PASTE YOUR REAL SUPABASE CREDENTIALS HERE — THIS IS THE ONLY FILE
/// YOU NEED TO EDIT TO CONNECT THE APP TO YOUR DATABASE.
///
/// Get both values from your Supabase project dashboard:
///   Settings → API → "Project URL" and "Publishable key" (or the legacy
///   "anon public" key, if your project still shows that naming).
///
/// Example:
///   supabaseUrl = 'https://scmxxnpxmjxhdnrekygh.supabase.co';
///   supabaseAnonKey = 'sb_publishable_xxxxxxxxxxxxxxxxxxxx';
const String supabaseUrl = 'https://scmxxnpxmjxhdnrekygh.supabase.co';
const String supabaseAnonKey = 'sb_publishable_NgEzbOcLU_56_Yx-FXmjbQ_HonYDM3C';

/// True once both values above have actually been replaced. Used by
/// main.dart to show a clear "Setup Required" screen instead of a
/// cryptic crash or a silently-broken app when they're still placeholders.
bool get isSupabaseConfigured =>
    supabaseUrl != 'YOUR_SUPABASE_URL' &&
    supabaseUrl.startsWith('http') &&
    supabaseAnonKey != 'YOUR_SUPABASE_ANON_KEY' &&
    supabaseAnonKey.isNotEmpty;

// ── OCR (receipt scanning) ───────────────────────────────────────────────
/// OCR.space API key (https://ocr.space/ocrapi). Free plan limits: 1 MB per
/// image, about 500 requests/day. This key ships inside the app, so treat it
/// as low-trust: use a free-tier key only, and rotate it if it leaks. For a
/// production release, proxy OCR calls through a Supabase Edge Function so
/// the key stays server-side.
const String ocrSpaceApiKey = 'K81418194588957';

bool get isOcrConfigured =>
    ocrSpaceApiKey.isNotEmpty && ocrSpaceApiKey != 'YOUR_OCR_SPACE_API_KEY';

// ── Password reset ───────────────────────────────────────────────────────
/// Deep link the password-reset email opens. It must ALSO be added in
/// Supabase Dashboard -> Authentication -> URL Configuration -> Redirect URLs,
/// and matches the intent-filter in android/.../AndroidManifest.xml.
const String authRedirectUrl = 'finora://login-callback/';

