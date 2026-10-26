import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:finora/services/supabase_service.dart';
import 'package:finora/services/profile_service.dart';
import 'package:finora/services/onboarding_service.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _loading = true;

  // Whether the current user still needs to complete the onboarding flow.
  // Defaults to false until we've actually checked, so we never bounce a
  // returning user into onboarding by mistake while the profile is loading.
  bool _needsOnboarding = false;
  bool _onboardingChecked = false;

  // True between the user opening a password-reset link and finishing (or
  // cancelling) the "set new password" screen. The router pins them there.
  bool _recoveringPassword = false;

  User? get user    => _user;
  bool get loading  => _loading;
  bool get isAuthenticated => _user != null;
  bool get needsOnboarding => _needsOnboarding;
  bool get onboardingChecked => _onboardingChecked;
  bool get recoveringPassword => _recoveringPassword;

  AuthProvider() {
    // Check current session on startup
    _user = Supabase.instance.client.auth.currentUser;
    _loading = false;
    if (_user != null) {
      // A non-null `currentUser` here means there's already a valid
      // session, so `auth.uid()` will resolve server-side and this is
      // safe to run against RLS-protected tables.
      _ensureProfileExists(_user!);
      _refreshOnboardingStatus(_user!.id).then((_) => notifyListeners());
    }

    // Listen to all auth state changes
    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      if (data.event == AuthChangeEvent.passwordRecovery) _recoveringPassword = true;
      _user    = data.session?.user;
      _loading = false;
      if (_user != null) {
        // `data.session` is non-null here (that's how `_user` got set), so
        // `auth.uid()` is populated and RLS-protected writes will succeed.
        await _ensureProfileExists(_user!);
        await _refreshOnboardingStatus(_user!.id);
      } else {
        _needsOnboarding = false;
        _onboardingChecked = false;
      }
      notifyListeners();
      debugPrint('Auth state: ${data.event} — user: ${_user?.id}');
    });
  }

  /// Creates the `profiles` row for [user] if it doesn't exist yet.
  ///
  /// This is the only place that writes to `profiles`, and it only ever
  /// runs when [user] comes from a confirmed, active session — i.e. when
  /// `auth.uid()` is guaranteed to equal `user.id` server-side. That's what
  /// the `profiles` RLS insert policy requires; calling this any earlier
  /// (e.g. right after `signUp()` while email confirmation is still
  /// pending and no session exists yet) is exactly what was causing the
  /// insert to be rejected by RLS.
  Future<void> _ensureProfileExists(User user) async {
    try {
      final existing = await ProfileService.getProfile(user.id);
      if (existing != null) return;

      final name = (user.userMetadata?['name'] as String?)?.trim();
      await ProfileService.upsertProfile(
        user.id,
        fullName: (name != null && name.isNotEmpty) ? name : 'User',
        email: user.email ?? '',
      );
    } catch (e) {
      debugPrint('_ensureProfileExists error: $e');
    }
  }

  /// Looks up the user's `onboarding` row and decides whether onboarding is
  /// needed. A missing row, or one without `onboarding_completed: true`,
  /// means this is effectively a first-time login. `onboarding_completed`
  /// lives on the `onboarding` table, not `profiles`.
  Future<void> _refreshOnboardingStatus(String userId) async {
    try {
      final onboarding = await OnboardingService.getOnboarding(userId);
      _needsOnboarding = onboarding == null || !onboarding.onboardingCompleted;
    } catch (e) {
      debugPrint('refreshOnboardingStatus error: $e');
      _needsOnboarding = false; // fail open so a network hiccup doesn't trap the user
    }
    _onboardingChecked = true;
  }

  /// Called by the onboarding screen once it has successfully saved answers.
  void markOnboardingComplete() {
    _needsOnboarding = false;
    notifyListeners();
  }

  Future<String?> signIn(String email, String password) async {
    try {
      _loading = true;
      notifyListeners();

      final res = await SupabaseService.signIn(email, password);
      _user = res.user;

      // A successful password sign-in always yields a real session, so
      // `auth.uid()` is populated and this write is safe against RLS.
      if (_user != null) {
        await _ensureProfileExists(_user!);
      }

      _loading = false;
      notifyListeners();
      return null;
    } on AuthException catch (e) {
      _loading = false;
      notifyListeners();
      return e.message;
    } catch (e) {
      _loading = false;
      notifyListeners();
      return 'Something went wrong. Please try again.';
    }
  }

  Future<String?> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      _loading = true;
      notifyListeners();

      final res = await SupabaseService.signUp(
        email: email,
        password: password,
        name: name,
      );

      // res.user is available even when email confirmation is ON
      _user = res.user;
      _loading = false;
      notifyListeners();

      debugPrint('SignUp — userId: ${res.user?.id}, session: ${res.session != null}');

      // Only write to `profiles` if signUp already returned an active
      // session (i.e. email confirmation is off / auto-confirmed). If
      // `res.session` is null, the user isn't authenticated yet — writing
      // now would fail the `profiles` RLS insert policy, since `auth.uid()`
      // has nothing to resolve to. In that case `_ensureProfileExists` runs
      // later instead, from the auth-state listener / `signIn()`, once a
      // real session exists (e.g. after the user confirms their email and
      // logs in).
      final userId = res.user?.id;
      if (userId != null && res.session != null) {
        await _ensureProfileExists(res.user!);
      }

      return null;
    } on AuthException catch (e) {
      _loading = false;
      notifyListeners();
      return e.message;
    } catch (e) {
      _loading = false;
      notifyListeners();
      debugPrint('SignUp error: $e');
      return 'Something went wrong. Please try again.';
    }
  }

  /// Sends a password-reset email. Returns an error message, or null on
  /// success. Success is reported the same way whether or not the address has
  /// an account, so the form never reveals which emails are registered.
  Future<String?> sendPasswordReset(String email) async {
    try {
      await SupabaseService.sendPasswordReset(email.trim());
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'Couldn\'t send the reset email. Check your connection and try again.';
    }
  }

  /// Checks the 6-digit code from the reset email. On success the user has a
  /// recovery session and the router sends them to the new-password screen.
  Future<String?> verifyRecoveryCode(String email, String code) async {
    try {
      final res = await SupabaseService.verifyRecoveryCode(email.trim(), code.trim());
      if (res.session == null) return 'Invalid or expired code. Request a new one.';
      _recoveringPassword = true;
      _user = res.session!.user;
      notifyListeners();
      return null;
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('expired') || m.contains('invalid')) {
        return 'That code is invalid or has expired. Request a new one.';
      }
      return e.message;
    } catch (_) {
      return 'Couldn\'t verify the code. Check your connection and try again.';
    }
  }

  /// Saves a new password for the recovery session. Null on success.
  Future<String?> updatePassword(String newPassword) async {
    try {
      await SupabaseService.updatePassword(newPassword);
      _recoveringPassword = false;
      notifyListeners();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'Couldn\'t update the password. Please try again.';
    }
  }

  /// Leaves the reset screen without changing the password.
  Future<void> cancelPasswordRecovery() async {
    _recoveringPassword = false;
    await signOut();
  }

  Future<void> signOut() async {
    await SupabaseService.signOut();
    _user = null;
    _needsOnboarding = false;
    _onboardingChecked = false;
    notifyListeners();
  }
}
