import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:finora/models/expense.dart';
import 'package:finora/config.dart';
import 'package:finora/services/ocr_service.dart';
import 'package:finora/utils/theme.dart';
import 'package:finora/widgets/glass_card.dart';

/// "📷 OCR Receipt Scanner". Extraction goes through [OCRService] (see
/// `ocr_service.dart`) — currently [DemoOCRService], which is honest about
/// not being connected to a real OCR engine yet rather than inventing
/// receipt data. Saving always hands off to the existing Add Expense
/// screen / `SupabaseService.addExpense` path — this screen never writes
/// to the database itself.
class ScanReceiptScreen extends StatefulWidget {
  const ScanReceiptScreen({super.key});

  @override
  State<ScanReceiptScreen> createState() => _ScanReceiptScreenState();
}

enum _ScanStage { picking, scanning, review }

class _ScanReceiptScreenState extends State<ScanReceiptScreen> {
  // Real OCR (OCR.space) when a key is configured; otherwise the honest
  // blank-fields demo service.
  final OCRService _ocrService =
      isOcrConfigured ? OcrSpaceService(apiKey: ocrSpaceApiKey) : DemoOCRService();
  final ImagePicker _picker = ImagePicker();

  _ScanStage _stage = _ScanStage.picking;
  Uint8List? _imageBytes;
  OCRResult? _result;
  String? _pickError;

  // Editable review fields
  final _merchantCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _category = 'Other';
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _merchantCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _pickError = null);
    try {
      // Downscale + compress so the photo stays under OCR.space's 1 MB free limit.
      final file = await _picker.pickImage(
          source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 70);
      if (file == null) return; // user cancelled
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _stage = _ScanStage.scanning;
      });
      await _runOcr(bytes);
    } catch (e) {
      debugPrint('OCR: image pick failed: $e');
      if (!mounted) return;
      setState(() => _pickError = 'Couldn\'t access the camera/gallery. Please try again.');
    }
  }

  Future<void> _runOcr(Uint8List bytes) async {
    debugPrint('OCR: started');
    try {
      final result = await _ocrService.scanReceipt(bytes);
      debugPrint('OCR: completed');
      if (!mounted) return;
      setState(() {
        _result = result;
        _merchantCtrl.text = result.merchant ?? '';
        _amountCtrl.text = result.amount != null ? result.amount!.toStringAsFixed(0) : '';
        _category = result.category ?? 'Other';
        _date = result.date ?? DateTime.now();
        _stage = _ScanStage.review;
      });
    } catch (e) {
      debugPrint('OCR: failed: $e');
      if (!mounted) return;
      setState(() {
        // Still let the user proceed and fill everything in manually
        // rather than dead-ending the screen.
        _result = const OCRResult(confidence: 0, isDemo: true);
        _stage = _ScanStage.review;
        _pickError = 'Scanning failed — you can still enter the details manually below.';
      });
    }
  }

  void _scanAgain() {
    setState(() {
      _stage = _ScanStage.picking;
      _imageBytes = null;
      _result = null;
      _pickError = null;
      _merchantCtrl.clear();
      _amountCtrl.clear();
      _category = 'Other';
      _date = DateTime.now();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _saveExpense() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount before saving'), backgroundColor: AppTheme.destructive),
      );
      return;
    }

    final draft = Expense(
      id: '',
      date: '${_date.year.toString().padLeft(4, '0')}-'
          '${_date.month.toString().padLeft(2, '0')}-'
          '${_date.day.toString().padLeft(2, '0')}',
      amount: amount,
      category: _category,
      mood: 'Neutral',
      paymentMode: 'UPI',
      isSubscription: false,
    );

    // Hand off to the existing Add Expense screen — it owns the one real
    // save path (SupabaseService.addExpense + SafeLock check).
    final saved = await context.push<bool>('/add-expense', extra: draft);
    if (!mounted) return;
    if (saved == true) context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('📷 OCR Receipt Scanner',
            style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.bold, fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppTheme.fg(isDark),
          onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (_pickError != null) ...[
              GlassCard(
                borderColor: AppTheme.warning.withOpacity(0.4),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppTheme.warning, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_pickError!, style: TextStyle(color: AppTheme.fg(isDark), fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_stage == _ScanStage.picking) _PickerView(isDark: isDark, onPick: _pickImage),
            if (_stage == _ScanStage.scanning && _imageBytes != null)
              _ScanningView(imageBytes: _imageBytes!, isDark: isDark),
            if (_stage == _ScanStage.review)
              _ReviewView(
                imageBytes: _imageBytes,
                result: _result,
                isDark: isDark,
                merchantCtrl: _merchantCtrl,
                amountCtrl: _amountCtrl,
                category: _category,
                date: _date,
                onCategoryChanged: (c) => setState(() => _category = c),
                onPickDate: _pickDate,
                onSave: _saveExpense,
                onScanAgain: _scanAgain,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Picker (initial) state ───────────────────────────────────────────────

class _PickerView extends StatelessWidget {
  final bool isDark;
  final ValueChanged<ImageSource> onPick;
  const _PickerView({required this.isDark, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        GlassCard(
          borderColor: AppTheme.primary.withOpacity(0.35),
          glow: true,
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
          child: Column(
            children: [
              Icon(Icons.receipt_long_rounded, color: AppTheme.primary, size: 52),
              const SizedBox(height: 16),
              Text('Scan a receipt',
                  style: TextStyle(color: AppTheme.fg(isDark), fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'Take a photo or choose one from your gallery to get started.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.camera_alt_rounded,
                label: 'Take Photo',
                onTap: () => onPick(ImageSource.camera),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                icon: Icons.photo_library_rounded,
                label: 'Choose from Gallery',
                onTap: () => onPick(ImageSource.gallery),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 14)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Scanning (animated) state ────────────────────────────────────────────

class _ScanningView extends StatefulWidget {
  final Uint8List imageBytes;
  final bool isDark;
  const _ScanningView({required this.imageBytes, required this.isDark});

  @override
  State<_ScanningView> createState() => _ScanningViewState();
}

class _ScanningViewState extends State<_ScanningView> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Image.memory(widget.imageBytes, width: double.infinity, height: 320, fit: BoxFit.cover),
              Container(color: Colors.black.withOpacity(0.25)),
              AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  return Positioned(
                    top: 320 * _ctrl.value,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          AppTheme.secondary.withOpacity(0),
                          AppTheme.secondary,
                          AppTheme.primary,
                          AppTheme.primary.withOpacity(0),
                        ]),
                        boxShadow: [BoxShadow(color: AppTheme.secondary.withOpacity(0.8), blurRadius: 8)],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
            ),
            const SizedBox(width: 10),
            Text('Scanning receipt...',
                style: TextStyle(color: AppTheme.fg(widget.isDark), fontSize: 13.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }
}

// ── Review (editable) state ──────────────────────────────────────────────

class _ReviewView extends StatelessWidget {
  final Uint8List? imageBytes;
  final OCRResult? result;
  final bool isDark;
  final TextEditingController merchantCtrl;
  final TextEditingController amountCtrl;
  final String category;
  final DateTime date;
  final ValueChanged<String> onCategoryChanged;
  final VoidCallback onPickDate;
  final VoidCallback onSave;
  final VoidCallback onScanAgain;

  const _ReviewView({
    required this.imageBytes,
    required this.result,
    required this.isDark,
    required this.merchantCtrl,
    required this.amountCtrl,
    required this.category,
    required this.date,
    required this.onCategoryChanged,
    required this.onPickDate,
    required this.onSave,
    required this.onScanAgain,
  });

  @override
  Widget build(BuildContext context) {
    final confidence = result?.confidence ?? 0;
    final isDemo = result?.isDemo ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (imageBytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(imageBytes!, width: double.infinity, height: 180, fit: BoxFit.cover),
          ),
        const SizedBox(height: 14),

        GlassCard(
          borderColor: AppTheme.primary.withOpacity(0.35),
          glow: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('DETECTED RECEIPT',
                      style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5)),
                  if (isDemo) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.muted(isDark).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('DEMO',
                          style: TextStyle(color: AppTheme.muted(isDark), fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                isDemo
                    ? 'No OCR engine is connected yet — please review and fill in the details below.'
                    : 'Detected ${confidence.toStringAsFixed(0)}% of key fields (merchant, amount, date) — please review before saving.',
                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11),
              ),
              const SizedBox(height: 16),

              Text('Merchant', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
              const SizedBox(height: 6),
              _EditField(controller: merchantCtrl, isDark: isDark, hint: 'e.g. D-Mart'),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Not saved yet — no database column for this.',
                    style: TextStyle(color: AppTheme.muted(isDark), fontSize: 10)),
              ),
              const SizedBox(height: 14),

              Text('Amount', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
              const SizedBox(height: 6),
              _EditField(
                controller: amountCtrl,
                isDark: isDark,
                hint: '0.00',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                prefix: '₹',
              ),
              const SizedBox(height: 14),

              Text('Category', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: AppConstants.categories.map((c) {
                  final selected = category == c;
                  return GestureDetector(
                    onTap: () => onCategoryChanged(c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: selected
                            ? const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary])
                            : null,
                        color: selected ? null : AppTheme.glass(isDark),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: selected ? Colors.transparent : AppTheme.border(isDark)),
                      ),
                      child: Text('${AppConstants.categoryEmojis[c] ?? '📦'} $c',
                          style: TextStyle(
                              color: selected ? Colors.white : AppTheme.fg(isDark),
                              fontSize: 11.5,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              Text('Date', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: onPickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.glass(isDark),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border(isDark)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, color: AppTheme.primary, size: 16),
                      const SizedBox(width: 8),
                      Text(DateFormat('dd MMM yyyy').format(date),
                          style: TextStyle(color: AppTheme.fg(isDark), fontSize: 13)),
                    ],
                  ),
                ),
              ),

              if (result != null && (result!.items.isNotEmpty || result!.tax != null)) ...[
                const SizedBox(height: 14),
                if (result!.items.isNotEmpty) ...[
                  Text('Items detected', style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(result!.items.join(', '), style: TextStyle(color: AppTheme.fg(isDark), fontSize: 12)),
                ],
                if (result!.tax != null) ...[
                  const SizedBox(height: 6),
                  Text('Tax: ₹${result!.tax!.toStringAsFixed(0)}',
                      style: TextStyle(color: AppTheme.fg(isDark), fontSize: 12)),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),

        GestureDetector(
          onTap: onSave,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.35), blurRadius: 16)],
            ),
            child: const Text('✓ Save Expense',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: onScanAgain,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.glass(isDark),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border(isDark)),
            ),
            child: Text('↻ Scan Again',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.fg(isDark), fontWeight: FontWeight.w600, fontSize: 14)),
          ),
        ),
      ],
    );
  }
}

class _EditField extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  final String hint;
  final TextInputType? keyboardType;
  final String? prefix;

  const _EditField({
    required this.controller,
    required this.isDark,
    required this.hint,
    this.keyboardType,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.glass(isDark),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Row(
        children: [
          if (prefix != null) ...[
            Text(prefix!, style: TextStyle(color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: TextStyle(color: AppTheme.fg(isDark), fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: AppTheme.muted(isDark)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
