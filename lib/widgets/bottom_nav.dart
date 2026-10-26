import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:finora/utils/theme.dart';

class BottomNav extends StatelessWidget {
  const BottomNav({super.key});

  static const _tabs = [
    _NavTab(path: '/dashboard', icon: Icons.grid_view_rounded,      label: 'Home'),
    _NavTab(path: '/expenses',  icon: Icons.receipt_long_rounded,    label: 'Expenses'),
    _NavTab(path: '/calendar',  icon: Icons.calendar_month_rounded,  label: 'Calendar'),
    _NavTab(path: '/predictions',icon: Icons.auto_awesome_rounded,   label: 'AI'),
    _NavTab(path: '/profile',   icon: Icons.person_rounded,          label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final location = GoRouterState.of(context).uri.toString();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark).withOpacity(0.95),
        border: Border(top: BorderSide(color: AppTheme.border(isDark))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _tabs.map((tab) {
              final isActive = location == tab.path;
              return GestureDetector(
                onTap: () => context.go(tab.path),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: isActive
                      ? BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        )
                      : null,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tab.icon,
                        color: isActive ? AppTheme.primary : AppTheme.muted(isDark),
                        size: 22),
                      const SizedBox(height: 3),
                      Text(tab.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: isActive ? AppTheme.primary : AppTheme.muted(isDark),
                        )),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _NavTab {
  final String path;
  final IconData icon;
  final String label;
  const _NavTab({required this.path, required this.icon, required this.label});
}
