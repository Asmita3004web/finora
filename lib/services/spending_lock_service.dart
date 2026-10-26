import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:finora/models/spending_lock.dart';
import 'package:finora/models/spending_lock_event.dart';

/// Thrown by every SpendingLockService call that fails, with a message
/// that's safe to show directly to the user (no raw PostgrestException
/// text, no stack trace) — see _wrap below. This exists specifically so
/// nothing in the SafeLock flow can fail *silently*: every caller gets
/// either a result or a SafeLockException, never an unhandled exception
/// that just vanishes into a button's onTap.
class SafeLockException implements Exception {
  final String message;
  SafeLockException(this.message);
  @override
  String toString() => message;
}

class SpendingLockService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<T> _wrap<T>(String action, Future<T> Function() op) async {
    try {
      return await op();
    } catch (e) {
      debugPrint('SafeLock: $action failed: $e');
      // PostgrestException code 42P01 (Postgres "relation does not exist")
      // or PGRST205 (PostgREST's own "table not found in schema cache")
      // both mean the same thing here: the table hasn't been created yet.
      final text = e.toString();
      if (text.contains('42P01') ||
          text.contains('PGRST205') ||
          text.contains('Could not find the table') ||
          (text.contains('relation') && text.contains('does not exist'))) {
        throw SafeLockException(
          'Database tables are missing. Run supabase/full_schema.sql, then supabase/safelock_migration.sql, in your Supabase SQL editor.',
        );
      }
      if (text.contains('SocketException') || text.contains('Failed host lookup') || text.contains('Connection')) {
        throw SafeLockException('Could not reach Supabase. Check your internet connection and that your project is not paused.');
      }
      if (text.contains('401') || text.contains('Invalid API key') || text.contains('JWT')) {
        throw SafeLockException('Supabase rejected the request (invalid URL/key). Double-check lib/config.dart.');
      }
      throw SafeLockException('Could not $action. Please try again.');
    }
  }

  // ── Fetch lock state for user ─────────────────────────────────────────────
  static Future<SpendingLock?> getLockState(String userId) => _wrap('load SafeLock state', () async {
        final data = await _client
            .from('spending_locks')
            .select()
            .eq('user_id', userId)
            .maybeSingle();
        if (data == null) return null;
        return SpendingLock.fromMap(data);
      });

  // ── Create default lock state for new user ────────────────────────────────
  static Future<SpendingLock> initLockState(String userId, double budgetLimit) => _wrap('set up SafeLock', () async {
        final data = await _client.from('spending_locks').upsert({
          'user_id': userId,
          'budget_limit': budgetLimit,
          'warning_count': 0,
          'lock_status': false,
          'emergency_count': 0,
          'last_emergency_used_at': null,
          'strict_mode': false,
          'enabled': true,
        }, onConflict: 'user_id').select().single();
        return SpendingLock.fromMap(data);
      });

  // ── Increment warning count, activate lock if >= 3 ───────────────────────
  static Future<SpendingLock> incrementWarning(
    String userId,
    int currentCount, {
    String? reason,
  }) =>
      _wrap('record SafeLock warning', () async {
        final newCount = currentCount + 1;
        final shouldLock = newCount >= 3;
        final now = DateTime.now().toIso8601String();
        final data = await _client.from('spending_locks').update({
          'warning_count': newCount,
          'lock_status': shouldLock,
          'last_warning_at': now,
        }).eq('user_id', userId).select().single();

        if (reason != null && reason.isNotEmpty) {
          await _tryRecordEvent(userId, reason, newCount);
        }
        return SpendingLock.fromMap(data);
      });

  // ── Recent Safety Events ──────────────────────────────────────────────────
  // Deliberately NOT wrapped in _wrap/SafeLockException: a missing events
  // table should never block a warning from being recorded, so this stays
  // best-effort and only ever logs to the console.
  static Future<void> _tryRecordEvent(String userId, String reason, int warningCountAtTime) async {
    try {
      await _client.from('spending_lock_events').insert({
        'user_id': userId,
        'reason': reason,
        'warning_count_at_time': warningCountAtTime,
      });
    } catch (e) {
      debugPrint('SafeLock: spending_lock_events insert skipped (table may not exist yet): $e');
    }
  }

  static Future<List<SpendingLockEvent>> getRecentEvents(String userId, {int limit = 5}) async {
    try {
      final data = await _client
          .from('spending_lock_events')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (data as List).map((e) => SpendingLockEvent.fromMap(e)).toList();
    } catch (e) {
      debugPrint('SafeLock: getRecentEvents returned none (table may not exist yet): $e');
      return [];
    }
  }

  // ── Record emergency unlock usage ─────────────────────────────────────────
  static Future<SpendingLock> recordEmergencyUnlock(String userId, int currentCount) =>
      _wrap('use emergency unlock', () async {
        final data = await _client.from('spending_locks').update({
          'emergency_count': currentCount + 1,
          'last_emergency_used_at': DateTime.now().toIso8601String(),
        }).eq('user_id', userId).select().single();
        return SpendingLock.fromMap(data);
      });

  // ── Toggle strict mode ────────────────────────────────────────────────────
  static Future<SpendingLock> toggleStrictMode(String userId, bool enabled) =>
      _wrap('update Strict Mode', () async {
        final data = await _client.from('spending_locks').update({
          'strict_mode': enabled,
        }).eq('user_id', userId).select().single();
        return SpendingLock.fromMap(data);
      });

  // ── SafeLock ON/OFF ────────────────────────────────────────────────────────
  static Future<SpendingLock> toggleEnabled(String userId, bool enabled) =>
      _wrap('update SafeLock status', () async {
        final data = await _client.from('spending_locks').update({
          'enabled': enabled,
        }).eq('user_id', userId).select().single();
        return SpendingLock.fromMap(data);
      });

  // ── Reset lock (user-initiated, requires confirmation in the UI) ─────────
  static Future<SpendingLock> resetLock(String userId) => _wrap('reset SafeLock', () async {
        final data = await _client.from('spending_locks').update({
          'warning_count': 0,
          'lock_status': false,
        }).eq('user_id', userId).select().single();
        return SpendingLock.fromMap(data);
      });

  // ── Update budget limit ───────────────────────────────────────────────────
  static Future<void> updateBudgetLimit(String userId, double limit) => _wrap('update budget limit', () async {
        await _client.from('spending_locks').update({
          'budget_limit': limit,
        }).eq('user_id', userId);
      });

  // ── Warning-notification preference (on-device, not Supabase-backed) ─────
  static Future<bool> getNotificationsEnabled(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('safelock_notifications_$userId') ?? true;
    } catch (e) {
      debugPrint('SafeLock: getNotificationsEnabled failed, defaulting to true: $e');
      return true;
    }
  }

  static Future<void> setNotificationsEnabled(String userId, bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('safelock_notifications_$userId', enabled);
    } catch (e) {
      debugPrint('SafeLock: setNotificationsEnabled failed: $e');
    }
  }
}
