import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:finora/models/profile.dart';

/// All Supabase access for the `profiles` table.
///
/// `profiles` only stores account info: full_name, email, phone_number,
/// profile_image. It never stores onboarding/financial data — see
/// [OnboardingService] for that. `profiles.id` is the signed-in user's auth
/// id (there is no separate `user_id` column on this table).
class ProfileService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<Profile?> getProfile(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      return row == null ? null : Profile.fromMap(row);
    } catch (e) {
      debugPrint('ProfileService.getProfile error: $e');
      return null;
    }
  }

  /// Creates or updates the profile row for [userId]. Only the four real
  /// `profiles` columns are ever written.
  ///
  /// Skips the write (returning `false`) if there is no active session for
  /// [userId]. The `profiles` RLS insert/update policies require
  /// `auth.uid() = id`; without a real session, `auth.uid()` is null on
  /// the server and the write would always be rejected — most commonly
  /// right after sign-up when email confirmation is pending and
  /// `res.user` is populated but `res.session` isn't yet. Checking here,
  /// in the one place that owns every write to `profiles`, avoids sending
  /// requests that can only ever fail RLS.
  static Future<bool> upsertProfile(
    String userId, {
    required String fullName,
    required String email,
    String? phoneNumber,
    String? profileImage,
  }) async {
    final sessionUserId = _client.auth.currentSession?.user.id;
    if (sessionUserId == null || sessionUserId != userId) {
      debugPrint(
        '⏭️ ProfileService.upsertProfile skipped for $userId — no active '
        'session yet (RLS would reject this write). It will be retried '
        'once the user has a real session.',
      );
      return false;
    }

    try {
      await _client.from('profiles').upsert({
        'id': userId,
        'full_name': fullName,
        'email': email,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        if (profileImage != null) 'profile_image': profileImage,
      }, onConflict: 'id');
      debugPrint('✅ Profile upserted for $userId');
      return true;
    } catch (e) {
      debugPrint('❌ ProfileService.upsertProfile error: $e');
      return false;
    }
  }
}
