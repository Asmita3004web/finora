// ═══════════════════════════════════════════════════════════════════════════════
// notification_service.dart
// Place: lib/services/notification_service.dart
// Full real-time notification system for Finora
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

// ── Unique notification IDs (never reuse IDs for different types) ─────────────
class NotifID {
  static const int overspending   = 1001;
  static const int nearLimit      = 1002;
  static const int spendingLocked = 1003;
  static const int dailyReminder  = 1004;
  static const int goalAchieved   = 1005;
}

// ── Android notification channel IDs ─────────────────────────────────────────
class NotifChannel {
  static const String alerts    = 'finora_alerts';
  static const String reminders = 'finora_reminders';
  static const String goals     = 'finora_goals';
}

class NotificationService {
  // Singleton
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  // Track last notification time to prevent duplicate spam
  static const String _prefKeyLastOverspend = 'last_overspend_notif';
  static const String _prefKeyLastNearLimit  = 'last_near_limit_notif';
  static const String _prefKeyLastGoal       = 'last_goal_notif';
  static const int _cooldownMinutes          = 30; // prevent same notif for 30 min

  // ── INIT ───────────────────────────────────────────────────────────────────

  /// Call this in main() before runApp()
  Future<void> initNotifications() async {
    // Initialize timezone data (needed for scheduled notifications)
    tz_data.initializeTimeZones();

    // ── Android settings ─────────────────────────────────────────────────────
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    // ── iOS settings ─────────────────────────────────────────────────────────
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create Android notification channels
    await _createChannels();

    debugPrint('✅ NotificationService initialized');
  }

  /// Create Android notification channels (required for Android 8+)
  Future<void> _createChannels() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    // Channel 1: Alerts (overspending, lock, warnings)
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        NotifChannel.alerts,
        'Budget Alerts',
        description: 'Overspending warnings and spending lock notifications',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFFEF4444),
      ),
    );

    // Channel 2: Reminders (daily reminder)
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        NotifChannel.reminders,
        'Daily Reminders',
        description: 'Daily expense logging reminder',
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
      ),
    );

    // Channel 3: Goals (savings achievements)
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        NotifChannel.goals,
        'Goal Achievements',
        description: 'Savings goal achievements and milestones',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFF22C55E),
      ),
    );
  }

  /// Handle notification tap — you can navigate user to a screen here
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.id} payload: ${response.payload}');
    // Navigation can be added here when needed
  }

  // ── PERMISSION ─────────────────────────────────────────────────────────────

  /// Request notification permission (Android 13+ / iOS)
  Future<bool> requestPermission() async {
    // iOS — handled by flutter_local_notifications init
    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
        alert: true, badge: true, sound: true);
      return granted ?? false;
    }

    // Android 13+
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Check if permission is granted
  Future<bool> isPermissionGranted() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  // ── COOLDOWN CHECK ─────────────────────────────────────────────────────────

  /// Returns true if we are allowed to send this notification
  /// (prevents spamming same notification repeatedly)
  Future<bool> _canSend(String prefKey) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSent = prefs.getInt(prefKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cooldown = _cooldownMinutes * 60 * 1000; // ms
    if (now - lastSent < cooldown) {
      debugPrint('⏳ Notification cooldown active for $prefKey');
      return false;
    }
    await prefs.setInt(prefKey, now);
    return true;
  }

  // ── NOTIFICATION DETAILS HELPERS ───────────────────────────────────────────

  NotificationDetails _alertDetails() => const NotificationDetails(
    android: AndroidNotificationDetails(
      NotifChannel.alerts,
      'Budget Alerts',
      channelDescription: 'Overspending warnings and lock notifications',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF7C3AED),
      styleInformation: BigTextStyleInformation(''),
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  NotificationDetails _reminderDetails() => const NotificationDetails(
    android: AndroidNotificationDetails(
      NotifChannel.reminders,
      'Daily Reminders',
      channelDescription: 'Daily expense logging reminder',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF7C3AED),
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  NotificationDetails _goalDetails() => const NotificationDetails(
    android: AndroidNotificationDetails(
      NotifChannel.goals,
      'Goal Achievements',
      channelDescription: 'Savings goal achievements',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF22C55E),
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC NOTIFICATION METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// A) Overspending Alert — user exceeded monthly/category budget
  Future<void> showOverspendingAlert({
    required double spent,
    required double limit,
  }) async {
    final canSend = await _canSend(_prefKeyLastOverspend);
    if (!canSend) return;

    final over = (spent - limit).toStringAsFixed(0);
    await _plugin.show(
      NotifID.overspending,
      '🚨 Overspending Alert',
      'You are ₹$over over your budget limit! Review your expenses.',
      _alertDetails(),
      payload: 'overspending',
    );
    debugPrint('✅ Overspending notification sent');
  }

  /// B) Near Limit Warning — spending reached 80% of budget
  Future<void> showBudgetWarning({
    required double spent,
    required double limit,
  }) async {
    final canSend = await _canSend(_prefKeyLastNearLimit);
    if (!canSend) return;

    final percent = ((spent / limit) * 100).toStringAsFixed(0);
    final remaining = (limit - spent).toStringAsFixed(0);
    await _plugin.show(
      NotifID.nearLimit,
      '⚠️ Budget Warning',
      'You\'ve used $percent% of your budget. Only ₹$remaining left!',
      _alertDetails(),
      payload: 'near_limit',
    );
    debugPrint('✅ Budget warning notification sent');
  }

  /// C) Spending Lock Alert — strict mode blocked extra spending
  Future<void> showLockAlert({bool isStrict = false}) async {
    final body = isStrict
        ? 'Strict mode is active. All spending is blocked for 24 hours.'
        : 'Your account is locked after 3 budget warnings. Use emergency unlock to continue.';

    await _plugin.show(
      NotifID.spendingLocked,
      '🔒 Spending Locked',
      body,
      _alertDetails(),
      payload: 'spending_locked',
    );
    debugPrint('✅ Lock notification sent');
  }

  /// D) Daily Reminder — scheduled every evening at set time
  Future<void> showReminder() async {
    await _plugin.show(
      NotifID.dailyReminder,
      '📝 Expense Reminder',
      'Don\'t forget to log today\'s expenses! Stay on top of your budget.',
      _reminderDetails(),
      payload: 'daily_reminder',
    );
    debugPrint('✅ Reminder notification sent');
  }

  /// Schedule daily reminder at a specific hour:minute every day
  Future<void> scheduleDailyReminder({int hour = 20, int minute = 0}) async {
    await cancelNotification(NotifID.dailyReminder);

    // Get India timezone (IST)
    final location = tz.getLocation('Asia/Kolkata');
    final now = tz.TZDateTime.now(location);
    var scheduledTime = tz.TZDateTime(location, now.year, now.month, now.day, hour, minute);

    // If time has already passed today, schedule for tomorrow
    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      NotifID.dailyReminder,
      '📝 Expense Reminder',
      'Don\'t forget to log today\'s expenses! Stay on top of your budget.',
      scheduledTime,
      _reminderDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily
      payload: 'daily_reminder',
    );
    debugPrint('✅ Daily reminder scheduled at $hour:$minute IST');
  }

  /// E) Savings Goal Achieved
  Future<void> showGoalAchieved({required double goalAmount}) async {
    final canSend = await _canSend(_prefKeyLastGoal);
    if (!canSend) return;

    await _plugin.show(
      NotifID.goalAchieved,
      '🎉 Goal Achieved!',
      'Amazing! You\'ve reached your savings goal of ₹${goalAmount.toStringAsFixed(0)}. Keep it up!',
      _goalDetails(),
      payload: 'goal_achieved',
    );
    debugPrint('✅ Goal achieved notification sent');
  }

  // ── SMART BUDGET CHECK ─────────────────────────────────────────────────────

  /// Call this after every expense is added.
  /// Automatically decides which notification to send.
  Future<void> checkAndNotify({
    required double totalSpent,
    required double budgetLimit,
    required double savingsGoal,
    required double monthlyIncome,
  }) async {
    if (budgetLimit <= 0) return;

    final percentage = totalSpent / budgetLimit;
    final savings    = monthlyIncome - totalSpent;

    if (percentage >= 1.0) {
      // Over budget
      await showOverspendingAlert(spent: totalSpent, limit: budgetLimit);
    } else if (percentage >= 0.8) {
      // At 80%+ of budget
      await showBudgetWarning(spent: totalSpent, limit: budgetLimit);
    }

    // Check savings goal
    if (savingsGoal > 0 && savings >= savingsGoal) {
      await showGoalAchieved(goalAmount: savingsGoal);
    }
  }

  // ── UTILITY ────────────────────────────────────────────────────────────────

  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _plugin.cancelAll();
  }
}
