import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's chosen AI Assistant avatar locally.
///
/// The task explicitly says "save locally or using the existing user
/// profile mechanism" and "do not create a new database table unless
/// required" — a local key/value pair is enough for a UI preference like
/// this, so it's kept out of Supabase entirely. Keyed by user id so a
/// shared device with multiple accounts doesn't leak one user's pick to
/// another.
class AiAvatarService {
  static const _prefix = 'ai_avatar_selection_';

  static Future<String?> getSelected(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_prefix$userId');
    } catch (e) {
      debugPrint('AiAvatarService.getSelected error: $e');
      return null;
    }
  }

  static Future<void> setSelected(String userId, String avatarId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$userId', avatarId);
    } catch (e) {
      debugPrint('AiAvatarService.setSelected error: $e');
    }
  }
}
