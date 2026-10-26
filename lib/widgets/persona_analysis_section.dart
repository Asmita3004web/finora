import 'package:flutter/material.dart';
import 'package:finora/models/analysis_result.dart';
import 'package:finora/utils/theme.dart';
import 'package:finora/widgets/glass_card.dart';

/// Display-only rendering of an [AnalysisResult]. All numbers and wording
/// come from PersonaAnalysisService — nothing is computed or hard-coded here.
class PersonaAnalysisSection extends StatelessWidget {
  final AnalysisResult result;
  final bool isDark;
  const PersonaAnalysisSection({super.key, required this.result, required this.isDark});

  String _inr(double v) => v < 0 ? '-₹${(-v).toStringAsFixed(0)}' : '₹${v.toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final c = result.common;
    final s = result.section;

    final overview = <AnalysisMetric>[
      AnalysisMetric(
        'Savings',
        c.savings == null ? 'Not enough data yet' : _inr(c.savings!),
        hint: c.incomeSource == 'declared' ? 'estimated' : null,
      ),
      AnalysisMetric('Savings rate',
          c.savingsRate == null ? 'Not enough data yet' : '${c.savingsRate!.toStringAsFixed(0)}%'),
      AnalysisMetric('Transactions', '${c.transactionCount}'),
      AnalysisMetric('Avg per transaction', _inr(c.avgPerTransaction)),
      AnalysisMetric(
        'Top category',
        c.topCategory == null ? '—' : c.topCategory!,
        hint: c.topCategoryShare == null ? null : '${c.topCategoryShare!.toStringAsFixed(0)}% of spend',
      ),
      AnalysisMetric(
        'Fixed vs variable',
        c.fixedTracked ? '${_inr(c.fixedTotal)} / ${_inr(c.variableTotal)}' : 'Not tracked',
      ),
      AnalysisMetric(
        'Budget used',
        c.budgetUsedPercent == null ? 'No budget set' : '${c.budgetUsedPercent!.toStringAsFixed(0)}%',
        hint: c.budgetUsedPercent == null ? null : 'this month',
      ),
    ];

    return GlassCard(
      borderColor: AppTheme.secondary.withOpacity(0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your Financial Persona',
              style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
          const SizedBox(height: 4),
          Text(result.persona ?? 'Not set yet',
              style: TextStyle(color: AppTheme.fg(isDark), fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),

          _heading('Financial Overview'),
          const SizedBox(height: 8),
          _grid(overview),
          const SizedBox(height: 18),

          _heading(s.title),
          const SizedBox(height: 8),
          if (s.notEnoughData)
            Text(s.message ?? 'Not enough data yet',
                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12.5))
          else ...[
            if (s.insight != null)
              Text(s.insight!,
                  style: TextStyle(color: AppTheme.fg(isDark), fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _grid(s.metrics),
            if (s.bars.isNotEmpty) ...[
              const SizedBox(height: 16),
              _subheading(s.barsTitle),
              const SizedBox(height: 8),
              _Bars(bars: s.bars, isDark: isDark),
            ],
            if (s.bars2.isNotEmpty) ...[
              const SizedBox(height: 16),
              _subheading(s.bars2Title),
              const SizedBox(height: 8),
              _Bars(bars: s.bars2, isDark: isDark),
            ],
            if (s.strengths.isNotEmpty) ...[
              const SizedBox(height: 16),
              _subheading('Strengths'),
              ...s.strengths.map((t) => _bullet('✅', t)),
            ],
            if (s.watch.isNotEmpty) ...[
              const SizedBox(height: 14),
              _subheading('Areas to watch'),
              ...s.watch.map((t) => _bullet('⚠️', t)),
            ],
            if (s.opportunities.isNotEmpty) ...[
              const SizedBox(height: 14),
              _subheading('Potential savings opportunities'),
              ...s.opportunities.map((t) => _bullet('💡', t)),
            ],
            if (s.note != null) ...[
              const SizedBox(height: 12),
              Text(s.note!, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 10.5)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _heading(String t) => Text(t,
      style: TextStyle(color: AppTheme.fg(isDark), fontSize: 13.5, fontWeight: FontWeight.w700));

  Widget _subheading(String? t) => Text(t ?? '',
      style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11.5, fontWeight: FontWeight.w600));

  Widget _bullet(String icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(color: AppTheme.fg(isDark), fontSize: 12.5)),
            ),
          ],
        ),
      );

  Widget _grid(List<AnalysisMetric> metrics) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = (constraints.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 10,
        children: metrics
            .map((m) => SizedBox(
                  width: w,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.label, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 10)),
                      const SizedBox(height: 2),
                      Text(m.value,
                          style: TextStyle(
                              color: AppTheme.secondary, fontSize: 13, fontWeight: FontWeight.bold)),
                      if (m.hint != null)
                        Text(m.hint!,
                            style: TextStyle(color: AppTheme.muted(isDark), fontSize: 9.5)),
                    ],
                  ),
                ))
            .toList(),
      );
    });
  }
}

/// Simple horizontal bars. Negative values are drawn in the warning colour.
class _Bars extends StatelessWidget {
  final List<AnalysisBar> bars;
  final bool isDark;
  const _Bars({required this.bars, required this.isDark});

  @override
  Widget build(BuildContext context) {
    var maxAbs = 0.0;
    for (final b in bars) {
      if (b.value.abs() > maxAbs) maxAbs = b.value.abs();
    }
    return Column(
      children: bars.map((b) {
        final frac = maxAbs > 0 ? (b.value.abs() / maxAbs).clamp(0.0, 1.0) : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 78,
                child: Text(b.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 8,
                    backgroundColor: AppTheme.border(isDark),
                    valueColor: AlwaysStoppedAnimation(
                        b.value < 0 ? AppTheme.warning : AppTheme.secondary),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(b.display, style: TextStyle(color: AppTheme.fg(isDark), fontSize: 11)),
            ],
          ),
        );
      }).toList(),
    );
  }
}
