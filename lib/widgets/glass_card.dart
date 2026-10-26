import 'package:flutter/material.dart';
import 'package:finora/utils/theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final VoidCallback? onTap;
  final bool glow;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
    this.onTap,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.glass(isDark),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor ?? AppTheme.border(isDark)),
          boxShadow: glow
              ? [BoxShadow(color: AppTheme.primary.withOpacity(0.2), blurRadius: 16)]
              : null,
        ),
        child: child,
      ),
    );
  }
}
