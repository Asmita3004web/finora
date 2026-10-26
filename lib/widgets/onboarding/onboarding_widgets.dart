import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:finora/utils/theme.dart';

/// Segmented progress bar shown at the top of every onboarding step.
class OnboardingProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final bool isDark;

  const OnboardingProgressBar({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps, (i) {
        final active = i <= currentStep;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == totalSteps - 1 ? 0 : 4),
            height: 5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: active ? null : AppTheme.glass(isDark),
              gradient: active
                  ? const LinearGradient(colors: [AppTheme.primary, AppTheme.teal])
                  : null,
            ),
          ).animate(target: active ? 1 : 0).scaleX(
                begin: 0.3,
                end: 1,
                duration: 280.ms,
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerLeft,
              ),
        );
      }),
    );
  }
}

/// A single tappable option card used for single-select questions.
class OnboardingOptionCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String? subtitle;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const OnboardingOptionCard({
    super.key,
    required this.emoji,
    required this.label,
    this.subtitle,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: subtitle != null ? 16 : 18),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [AppTheme.primary.withOpacity(0.18), AppTheme.teal.withOpacity(0.12)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: selected ? null : AppTheme.surface(isDark),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border(isDark),
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: AppTheme.fg(isDark),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12.5, color: AppTheme.muted(isDark), height: 1.3),
                    ),
                  ],
                ],
              ),
            ),
            AnimatedScale(
              scale: selected ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [AppTheme.primary, AppTheme.teal]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A multi-select variant (checkbox-style) used for the fixed-expenses step.
class OnboardingMultiSelectChip extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const OnboardingMultiSelectChip({
    super.key,
    required this.emoji,
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary])
              : null,
          color: selected ? null : AppTheme.surface(isDark),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border(isDark),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppTheme.fg(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Consistent heading block used across steps ("emoji title" + description).
class OnboardingHeader extends StatelessWidget {
  final String title;
  final String? description;
  final bool isDark;

  const OnboardingHeader({
    super.key,
    required this.title,
    this.description,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.fg(isDark),
            height: 1.25,
          ),
        ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.12, end: 0, curve: Curves.easeOutCubic),
        if (description != null) ...[
          const SizedBox(height: 8),
          Text(
            description!,
            style: TextStyle(fontSize: 14.5, color: AppTheme.muted(isDark), height: 1.45),
          ).animate().fadeIn(delay: 100.ms, duration: 350.ms).slideY(begin: 0.12, end: 0, curve: Curves.easeOutCubic),
        ],
      ],
    );
  }
}
