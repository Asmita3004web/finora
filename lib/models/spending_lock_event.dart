/// A single "Recent Safety Event" — one row per warning SafeLock issued.
/// Backed by the new `spending_lock_events` table (see
/// supabase/safelock_migration.sql). Purely a log for the UI; the
/// authoritative warning count still lives on `spending_locks`.
class SpendingLockEvent {
  final String id;
  final String userId;
  final String reason;
  final int warningCountAtTime;
  final DateTime createdAt;

  SpendingLockEvent({
    required this.id,
    required this.userId,
    required this.reason,
    required this.warningCountAtTime,
    required this.createdAt,
  });

  factory SpendingLockEvent.fromMap(Map<String, dynamic> map) {
    return SpendingLockEvent(
      id: map['id'] as String? ?? '',
      userId: map['user_id'] as String? ?? '',
      reason: map['reason'] as String? ?? 'Unusual spending detected',
      warningCountAtTime: (map['warning_count_at_time'] as int?) ?? 0,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
