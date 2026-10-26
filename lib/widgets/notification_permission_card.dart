// ═══════════════════════════════════════════════════════════════════════════════
// notification_permission_card.dart
// Place: lib/widgets/notification_permission_card.dart
// Shows a polite permission request card when notifications are disabled
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:finora/services/notification_service.dart';
import 'package:finora/utils/theme.dart';

class NotificationPermissionCard extends StatefulWidget {
  const NotificationPermissionCard({super.key});

  @override
  State<NotificationPermissionCard> createState() =>
      _NotificationPermissionCardState();
}

class _NotificationPermissionCardState
    extends State<NotificationPermissionCard> {
  bool _isGranted  = true;  // Assume granted until we check
  bool _isDismissed = false;
  bool _checking   = true;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final granted = await NotificationService().isPermissionGranted();
    if (mounted) {
      setState(() {
        _isGranted = granted;
        _checking  = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    final granted = await NotificationService().requestPermission();
    if (mounted) {
      setState(() => _isGranted = granted);
      if (!granted) {
        // If still denied, open app settings
        await openAppSettings();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't show if: checking, already granted, or dismissed by user
    if (_checking || _isGranted || _isDismissed) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications_off_rounded,
                    color: AppTheme.warning, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Notifications Disabled',
                      style: TextStyle(
                        color: AppTheme.fg(isDark),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      )),
                    Text('Enable to get budget alerts & reminders',
                      style: TextStyle(
                        color: AppTheme.muted(isDark), fontSize: 11)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _isDismissed = true),
                child: Icon(Icons.close_rounded,
                    color: AppTheme.muted(isDark), size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _isDismissed = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.glass(isDark),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border(isDark)),
                  ),
                  child: Text('Not Now',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _requestPermission,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.teal]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('Enable Now',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ── Notification Settings Card for Profile Screen ─────────────────────────────
class NotificationSettingsCard extends StatefulWidget {
  const NotificationSettingsCard({super.key});

  @override
  State<NotificationSettingsCard> createState() =>
      _NotificationSettingsCardState();
}

class _NotificationSettingsCardState extends State<NotificationSettingsCard> {
  bool _isGranted   = false;
  bool _checking    = true;
  int  _reminderHour = 20;

  final List<Map<String, dynamic>> _hours = [
    {'label': '6 PM', 'hour': 18},
    {'label': '7 PM', 'hour': 19},
    {'label': '8 PM', 'hour': 20},
    {'label': '9 PM', 'hour': 21},
    {'label': '10 PM', 'hour': 22},
  ];

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final granted = await NotificationService().isPermissionGranted();
    if (mounted) setState(() { _isGranted = granted; _checking = false; });
  }

  Future<void> _toggle() async {
    if (_isGranted) {
      await openAppSettings();
    } else {
      final granted = await NotificationService().requestPermission();
      if (mounted) setState(() => _isGranted = granted);
      if (!granted && mounted) await openAppSettings();
    }
  }

  Future<void> _setReminder(int hour) async {
    setState(() => _reminderHour = hour);
    await NotificationService().scheduleDailyReminder(hour: hour, minute: 0);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Daily reminder set for ${_hours.firstWhere((h) => h['hour'] == hour)['label']}'),
        backgroundColor: AppTheme.success,
      ));
    }
  }

  Future<void> _testNotification() async {
    await NotificationService().showReminder();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Test notification sent! Check your notification panel.'),
        backgroundColor: AppTheme.success,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_checking) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.notifications_rounded,
                  color: AppTheme.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Text('Notifications',
              style: TextStyle(
                color: AppTheme.fg(isDark),
                fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            Switch(
              value: _isGranted,
              onChanged: (_) => _toggle(),
              activeColor: AppTheme.primary,
            ),
          ]),

          if (!_isGranted) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    color: AppTheme.warning, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Enable notifications to get budget alerts and daily reminders.',
                    style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12),
                  ),
                ),
              ]),
            ),
          ],

          if (_isGranted) ...[
            const SizedBox(height: 16),
            // What notifications you get
            _NotifItem(isDark: isDark, icon: '🚨', label: 'Overspending Alert',   desc: 'When you exceed budget'),
            _NotifItem(isDark: isDark, icon: '⚠️', label: 'Budget Warning',       desc: 'At 80% of budget'),
            _NotifItem(isDark: isDark, icon: '🔒', label: 'Spending Lock Alert',  desc: 'When account is locked'),
            _NotifItem(isDark: isDark, icon: '🎉', label: 'Goal Achievement',     desc: 'When savings goal is met'),
            const SizedBox(height: 16),
            // Daily reminder time picker
            Text('Daily Reminder Time',
              style: TextStyle(color: AppTheme.fg(isDark),
                fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _hours.map((h) {
                final selected = _reminderHour == h['hour'];
                return GestureDetector(
                  onTap: () => _setReminder(h['hour'] as int),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: selected ? const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.teal]) : null,
                      color: selected ? null : AppTheme.glass(isDark),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: selected ? Colors.transparent : AppTheme.border(isDark)),
                    ),
                    child: Text(h['label'] as String,
                      style: TextStyle(
                        color: selected ? Colors.white : AppTheme.muted(isDark),
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      )),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Test notification button
            GestureDetector(
              onTap: _testNotification,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.glass(isDark),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.send_rounded, color: AppTheme.primary, size: 16),
                  const SizedBox(width: 8),
                  Text('Send Test Notification',
                    style: TextStyle(color: AppTheme.primary,
                      fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotifItem extends StatelessWidget {
  final bool isDark;
  final String icon, label, desc;
  const _NotifItem({required this.isDark, required this.icon,
    required this.label, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: AppTheme.fg(isDark),
            fontSize: 13, fontWeight: FontWeight.w500)),
          Text(desc, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.success.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text('ON',
            style: TextStyle(color: AppTheme.success, fontSize: 10,
              fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}
