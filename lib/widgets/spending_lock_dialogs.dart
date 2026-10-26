import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finora/utils/theme.dart';
import 'package:finora/services/spending_lock_provider.dart';
import 'package:finora/services/theme_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WARNING DIALOG  (shown when budget exceeded, up to 3 times)
// ─────────────────────────────────────────────────────────────────────────────
class SpendingWarningDialog extends StatelessWidget {
  final int warningCount;
  final double spent;
  final double limit;
  final VoidCallback onContinue;
  /// Real reasons from SafeLockRiskEngine for this specific warning.
  /// Optional so existing call sites without it still compile.
  final List<String> reasons;

  const SpendingWarningDialog({
    super.key,
    required this.warningCount,
    required this.spent,
    required this.limit,
    required this.onContinue,
    this.reasons = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final over = spent - limit;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface(isDark),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.warning.withOpacity(0.5), width: 1.5),
          boxShadow: [BoxShadow(color: AppTheme.warning.withOpacity(0.2), blurRadius: 30)],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 34),
            ),
            const SizedBox(height: 16),
            Text('Budget Warning ${warningCount}/3',
              style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold,
                color: AppTheme.fg(isDark),
              )),
            const SizedBox(height: 8),
            Text(
              'You\'ve exceeded your monthly limit by ₹${over.toStringAsFixed(0)}.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted(isDark), fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              '${3 - warningCount} warning(s) left before account locks.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.warning, fontSize: 13, fontWeight: FontWeight.w500),
            ),
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: reasons.take(3).map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.circle, size: 6, color: AppTheme.warning),
                    const SizedBox(width: 8),
                    Expanded(child: Text(r, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12.5))),
                  ]),
                )).toList(),
              ),
            ],
            const SizedBox(height: 20),
            _WarningBar(count: warningCount),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.muted(isDark),
                    side: BorderSide(color: AppTheme.border(isDark)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () { Navigator.pop(context); onContinue(); },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.warning,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Continue Anyway', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _WarningBar extends StatelessWidget {
  final int count;
  const _WarningBar({required this.count});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final filled = i < count;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 60, height: 8,
          decoration: BoxDecoration(
            color: filled ? AppTheme.warning : AppTheme.warning.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOCK DIALOG  (shown when lockStatus = true and user tries to add expense)
// ─────────────────────────────────────────────────────────────────────────────
class SpendingLockDialog extends StatefulWidget {
  final double amount;
  final double savingsGoal;
  final double totalSpent;
  final double monthlyIncome;
  final int emergencyLeft;
  final Future<bool> Function(String reason) onEmergencyUnlock;

  const SpendingLockDialog({
    super.key,
    required this.amount,
    required this.savingsGoal,
    required this.totalSpent,
    required this.monthlyIncome,
    required this.emergencyLeft,
    required this.onEmergencyUnlock,
  });

  @override
  State<SpendingLockDialog> createState() => _SpendingLockDialogState();
}

class _SpendingLockDialogState extends State<SpendingLockDialog> {
  String? _selectedReason;
  final _otherCtrl = TextEditingController();
  bool _confirmed = false;
  bool _submitting = false;
  bool _canSubmit = false;
  int _countdown = 10;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _otherCtrl.dispose();
    super.dispose();
  }

  void _startCountdown() {
    setState(() { _confirmed = true; _countdown = 10; _canSubmit = false; });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _countdown--;
        if (_countdown <= 0) { t.cancel(); _canSubmit = true; }
      });
    });
  }

  Future<void> _submit() async {
    final reason = _selectedReason == 'Other' ? _otherCtrl.text : _selectedReason ?? '';
    setState(() => _submitting = true);
    final ok = await widget.onEmergencyUnlock(reason);
    if (!mounted) return;
    setState(() => _submitting = false);
    Navigator.pop(context, ok);
  }

  bool get _reasonValid {
    if (_selectedReason == null) return false;
    if (_selectedReason == 'Other') return _otherCtrl.text.trim().length >= 20;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final projectedSavings = widget.monthlyIncome - widget.totalSpent - widget.amount;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface(isDark),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.destructive.withOpacity(0.5), width: 1.5),
          boxShadow: [BoxShadow(color: AppTheme.destructive.withOpacity(0.2), blurRadius: 30)],
        ),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.destructive.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.lock_rounded, color: AppTheme.destructive, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Spending Lock Active',
                      style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold,
                        color: AppTheme.fg(isDark),
                      )),
                    Text("You've crossed your limit 3 times",
                      style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
                  ],
                )),
              ]),
              const SizedBox(height: 16),

              // Reflection prompt
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.destructive.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.destructive.withOpacity(0.2)),
                ),
                child: Text(
                  '"You\'ve crossed your limit 3 times. Are you sure this is necessary?"',
                  style: TextStyle(
                    color: AppTheme.destructive,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Savings impact
              _SavingsImpactCard(
                isDark: isDark,
                savingsGoal: widget.savingsGoal,
                currentSavings: widget.monthlyIncome - widget.totalSpent,
                projectedSavings: projectedSavings,
                expenseAmount: widget.amount,
              ),
              const SizedBox(height: 16),

              // Emergency left badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Icon(Icons.bolt_rounded, color: AppTheme.warning, size: 18),
                  const SizedBox(width: 8),
                  Text('${widget.emergencyLeft}/3 emergency unlocks left this week',
                    style: TextStyle(color: AppTheme.warning, fontSize: 13, fontWeight: FontWeight.w500)),
                ]),
              ),

              if (widget.emergencyLeft <= 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.destructive.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    Icon(Icons.block_rounded, color: AppTheme.destructive),
                    const SizedBox(width: 10),
                    Expanded(child: Text('No emergency unlocks left this week.',
                      style: TextStyle(color: AppTheme.fg(isDark), fontSize: 13))),
                  ]),
                ),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.muted(isDark),
                    side: BorderSide(color: AppTheme.border(isDark)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Close'),
                )),
              ] else ...[
                const SizedBox(height: 16),
                // Reason selector
                Text('Select Emergency Reason',
                  style: TextStyle(
                    color: AppTheme.fg(isDark),
                    fontSize: 14, fontWeight: FontWeight.w600,
                  )),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  'Medical', 'Family', 'Urgent Bill', 'Other'
                ].map((r) => _ReasonChip(
                  label: r,
                  selected: _selectedReason == r,
                  isDark: isDark,
                  onTap: () => setState(() => _selectedReason = r),
                )).toList()),

                if (_selectedReason == 'Other') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _otherCtrl,
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: AppTheme.fg(isDark), fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Explain your reason (min 20 characters)...',
                      hintStyle: TextStyle(color: AppTheme.muted(isDark), fontSize: 12),
                      filled: true,
                      fillColor: AppTheme.card(isDark),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.border(isDark)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.border(isDark)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.primary),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                      counterText: '${_otherCtrl.text.length}/20 min',
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                if (!_confirmed) ...[
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.muted(isDark),
                        side: BorderSide(color: AppTheme.border(isDark)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('Cancel'),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton(
                      onPressed: _reasonValid ? _startCountdown : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.destructive,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppTheme.destructive.withOpacity(0.3),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('Confirm', style: TextStyle(fontWeight: FontWeight.w600)),
                    )),
                  ]),
                ] else ...[
                  // Countdown + final submit
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.card(isDark),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(children: [
                      if (!_canSubmit) ...[
                        Text('Take a moment to reconsider...',
                          style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
                        const SizedBox(height: 8),
                        Stack(alignment: Alignment.center, children: [
                          SizedBox(width: 56, height: 56,
                            child: CircularProgressIndicator(
                              value: (10 - _countdown) / 10,
                              backgroundColor: AppTheme.border(isDark),
                              color: AppTheme.destructive,
                              strokeWidth: 4,
                            )),
                          Text('$_countdown',
                            style: TextStyle(
                              color: AppTheme.fg(isDark),
                              fontSize: 20, fontWeight: FontWeight.bold,
                            )),
                        ]),
                      ] else ...[
                        SizedBox(width: double.infinity, child: ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.destructive,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _submitting
                              ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text('Submit Emergency Expense',
                                  style: TextStyle(fontWeight: FontWeight.w600)),
                        )),
                      ],
                    ]),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  const _ReasonChip({required this.label, required this.selected, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withOpacity(0.2) : AppTheme.card(isDark),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border(isDark),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(label,
          style: TextStyle(
            color: selected ? AppTheme.primary : AppTheme.muted(isDark),
            fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          )),
      ),
    );
  }
}

class _SavingsImpactCard extends StatelessWidget {
  final bool isDark;
  final double savingsGoal;
  final double currentSavings;
  final double projectedSavings;
  final double expenseAmount;
  const _SavingsImpactCard({
    required this.isDark,
    required this.savingsGoal,
    required this.currentSavings,
    required this.projectedSavings,
    required this.expenseAmount,
  });

  @override
  Widget build(BuildContext context) {
    final willMeetGoal = savingsGoal <= 0 || projectedSavings >= savingsGoal;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.savings_rounded, color: AppTheme.teal, size: 18),
            const SizedBox(width: 8),
            Text('Goal Impact', style: TextStyle(
              color: AppTheme.fg(isDark), fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          _ImpactRow(isDark: isDark, label: 'Savings goal', value: '₹${savingsGoal.toStringAsFixed(0)}', color: AppTheme.teal),
          _ImpactRow(isDark: isDark, label: 'Current savings', value: '₹${currentSavings.toStringAsFixed(0)}', color: AppTheme.fg(isDark)),
          _ImpactRow(isDark: isDark, label: 'This expense', value: '-₹${expenseAmount.toStringAsFixed(0)}', color: AppTheme.destructive),
          Divider(height: 16),
          _ImpactRow(
            isDark: isDark,
            label: 'Projected savings',
            value: '₹${projectedSavings.toStringAsFixed(0)}',
            color: willMeetGoal ? AppTheme.success : AppTheme.destructive,
            bold: true,
          ),
          if (!willMeetGoal && savingsGoal > 0) ...[
            const SizedBox(height: 6),
            Text('⚠️ This expense will prevent you from meeting your savings goal.',
              style: TextStyle(color: AppTheme.warning, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _ImpactRow extends StatelessWidget {
  final bool isDark;
  final String label;
  final String value;
  final Color color;
  final bool bold;
  const _ImpactRow({required this.isDark, required this.label, required this.value, required this.color, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
        Text(value, style: TextStyle(color: color, fontSize: 12,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STRICT LOCK DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class StrictLockDialog extends StatelessWidget {
  const StrictLockDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface(isDark),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.destructive.withOpacity(0.6), width: 2),
          boxShadow: [BoxShadow(color: AppTheme.destructive.withOpacity(0.3), blurRadius: 30)],
        ),
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.block_rounded, color: AppTheme.destructive, size: 52),
          const SizedBox(height: 16),
          Text('Strict Mode Active', style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.fg(isDark))),
          const SizedBox(height: 10),
          Text(
            'All expenses are blocked for 24 hours after 3 warnings.\nOnly emergency entries are allowed.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.muted(isDark), height: 1.6),
          ),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.muted(isDark),
              side: BorderSide(color: AppTheme.border(isDark)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text('Got it'),
          )),
        ]),
      ),
    );
  }
}
