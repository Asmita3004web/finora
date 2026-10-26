/// SafeLock state, backed by the real `spending_locks` table (one row per
/// user). `enabled` and `last_warning_at` are new columns added by
/// `supabase/safelock_migration.sql` — see that file for the exact SQL
/// and for why nothing here silently invents a second table.
class SpendingLock {
  final String userId;
  final double budgetLimit;
  final int warningCount;
  final bool lockStatus; // true once warningCount >= 3 ("ACTIVE")
  final int emergencyCount;
  final DateTime? lastEmergencyUsedAt;
  final bool strictMode;

  /// Whether SafeLock monitoring is turned on at all. When false the
  /// status is always "PAUSED" and no new warnings are ever generated,
  /// regardless of spending — this is the user-facing ON/OFF toggle.
  final bool enabled;

  /// When the most recent warning was recorded. Used both to show
  /// "Recent Safety Events" timing and to stop the same risk condition
  /// from firing more than once for the same transaction.
  final DateTime? lastWarningAt;

  SpendingLock({
    required this.userId,
    required this.budgetLimit,
    required this.warningCount,
    required this.lockStatus,
    required this.emergencyCount,
    this.lastEmergencyUsedAt,
    required this.strictMode,
    this.enabled = true,
    this.lastWarningAt,
  });

  factory SpendingLock.fromMap(Map<String, dynamic> map) {
    return SpendingLock(
      userId: map['user_id'] as String? ?? '',
      budgetLimit: double.tryParse(map['budget_limit']?.toString() ?? '0') ?? 0,
      warningCount: (map['warning_count'] as int?) ?? 0,
      lockStatus: map['lock_status'] as bool? ?? false,
      emergencyCount: (map['emergency_count'] as int?) ?? 0,
      lastEmergencyUsedAt: map['last_emergency_used_at'] != null
          ? DateTime.tryParse(map['last_emergency_used_at'].toString())
          : null,
      strictMode: map['strict_mode'] as bool? ?? false,
      // Both new columns are nullable/defaulted in the migration, so a
      // row written before the migration ran still parses fine: SafeLock
      // defaults to "on" with no prior warning timestamp.
      enabled: map['enabled'] as bool? ?? true,
      lastWarningAt: map['last_warning_at'] != null
          ? DateTime.tryParse(map['last_warning_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'user_id': userId,
    'budget_limit': budgetLimit,
    'warning_count': warningCount,
    'lock_status': lockStatus,
    'emergency_count': emergencyCount,
    'last_emergency_used_at': lastEmergencyUsedAt?.toIso8601String(),
    'strict_mode': strictMode,
    'enabled': enabled,
    'last_warning_at': lastWarningAt?.toIso8601String(),
  };

  SpendingLock copyWith({
    double? budgetLimit,
    int? warningCount,
    bool? lockStatus,
    int? emergencyCount,
    DateTime? lastEmergencyUsedAt,
    bool? strictMode,
    bool? enabled,
    DateTime? lastWarningAt,
  }) {
    return SpendingLock(
      userId: userId,
      budgetLimit: budgetLimit ?? this.budgetLimit,
      warningCount: warningCount ?? this.warningCount,
      lockStatus: lockStatus ?? this.lockStatus,
      emergencyCount: emergencyCount ?? this.emergencyCount,
      lastEmergencyUsedAt: lastEmergencyUsedAt ?? this.lastEmergencyUsedAt,
      strictMode: strictMode ?? this.strictMode,
      enabled: enabled ?? this.enabled,
      lastWarningAt: lastWarningAt ?? this.lastWarningAt,
    );
  }

  /// Returns how many emergency unlocks are left this week
  int get emergencyUnlocksLeftThisWeek {
    if (lastEmergencyUsedAt == null) return 3;
    final diff = DateTime.now().difference(lastEmergencyUsedAt!);
    if (diff.inDays >= 7) return 3; // reset each week
    return (3 - emergencyCount).clamp(0, 3);
  }

  bool get isStrictLocked {
    if (!strictMode || lastEmergencyUsedAt == null) return false;
    final diff = DateTime.now().difference(lastEmergencyUsedAt!);
    return warningCount >= 3 && diff.inHours < 24;
  }

  /// Single source of truth for the three states the SafeLock page shows.
  /// PAUSED wins even over an active lock — a user who turned SafeLock off
  /// should never see "ACTIVE".
  SafeLockStatus get status {
    if (!enabled) return SafeLockStatus.paused;
    if (lockStatus) return SafeLockStatus.active;
    return SafeLockStatus.monitoring;
  }
}

enum SafeLockStatus { active, monitoring, paused }

extension SafeLockStatusLabel on SafeLockStatus {
  String get label {
    switch (this) {
      case SafeLockStatus.active:
        return 'ACTIVE';
      case SafeLockStatus.monitoring:
        return 'MONITORING';
      case SafeLockStatus.paused:
        return 'PAUSED';
    }
  }
}
