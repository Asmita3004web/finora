import 'dart:convert';

import 'package:http/http.dart' as http;

/// Best-effort data extracted from a receipt image. Every field is
/// nullable because OCR may fail to detect it — callers must never treat
/// a null/empty field as "zero" or invent a value to fill the gap.
class OCRResult {
  final String? merchant;
  final double? amount;
  final String? category;
  final DateTime? date;
  final List<String> items;
  final double? tax;
  final double confidence; // 0–100
  final bool isDemo;

  const OCRResult({
    this.merchant,
    this.amount,
    this.category,
    this.date,
    this.items = const [],
    this.tax,
    required this.confidence,
    required this.isDemo,
  });
}

/// Interface for turning a receipt image into structured data. Swap
/// `DemoOCRService` for a real engine (e.g. Google ML Kit text
/// recognition, a cloud OCR API) later without touching the Scan Receipt
/// screen — it only ever talks to this interface.
abstract class OCRService {
  /// [imageBytes] is the raw image data (JPEG/PNG) from the camera or
  /// gallery picker.
  Future<OCRResult> scanReceipt(List<int> imageBytes);
}

/// No real OCR engine is connected yet. This implementation is honest
/// about that: it returns an empty, clearly-marked demo result (0%
/// confidence, `isDemo: true`) rather than inventing merchant/amount
/// values, so the review screen simply opens with blank fields for the
/// user to fill in manually. Replace this class with a real OCR-backed
/// implementation to make the screen fully automatic.
class DemoOCRService implements OCRService {
  @override
  Future<OCRResult> scanReceipt(List<int> imageBytes) async {
    // Simulated processing delay so the "Scanning receipt..." animation
    // reads naturally — no actual image analysis happens here yet.
    await Future.delayed(const Duration(milliseconds: 1200));
    return const OCRResult(
      merchant: null,
      amount: null,
      category: null,
      date: null,
      items: [],
      tax: null,
      confidence: 0,
      isDemo: true,
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Real OCR via OCR.space
// ───────────────────────────────────────────────────────────────────────────

/// Thrown when OCR cannot run or the API reports an error. The Scan Receipt
/// screen catches any exception and falls back to manual entry.
class OcrException implements Exception {
  final String message;
  const OcrException(this.message);
  @override
  String toString() => 'OcrException: $message';
}

/// Receipt OCR backed by https://ocr.space (free tier: 1 MB per image).
///
/// Only the raw text comes from the API; merchant / amount / date / tax /
/// category are then extracted by [ReceiptParser]. Every field stays null
/// when it can't be found with reasonable confidence — nothing is invented.
class OcrSpaceService implements OCRService {
  final String apiKey;
  final http.Client _client;
  final Duration timeout;

  static const _endpoint = 'https://api.ocr.space/parse/image';

  /// OCR.space free plan rejects files above 1 MB.
  static const maxBytes = 1024 * 1024;

  OcrSpaceService({
    required this.apiKey,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  @override
  Future<OCRResult> scanReceipt(List<int> imageBytes) async {
    if (imageBytes.isEmpty) throw const OcrException('Empty image.');
    if (imageBytes.length > maxBytes) {
      throw const OcrException('Image is larger than 1 MB (OCR.space free limit).');
    }

    final isPng = imageBytes.length > 3 &&
        imageBytes[0] == 0x89 &&
        imageBytes[1] == 0x50 &&
        imageBytes[2] == 0x4E;

    final request = http.MultipartRequest('POST', Uri.parse(_endpoint))
      ..headers['apikey'] = apiKey
      ..fields['language'] = 'eng'
      ..fields['OCREngine'] = '2'
      ..fields['isTable'] = 'true' // keeps receipt lines in reading order
      ..fields['scale'] = 'true'
      ..fields['detectOrientation'] = 'true'
      ..fields['filetype'] = isPng ? 'PNG' : 'JPG'
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        imageBytes,
        filename: isPng ? 'receipt.png' : 'receipt.jpg',
      ));

    final streamed = await _client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed).timeout(timeout);
    if (response.statusCode != 200) {
      throw OcrException('OCR service returned HTTP ${response.statusCode}.');
    }
    return parseResponse(response.body);
  }

  /// Turns an OCR.space JSON response body into an [OCRResult].
  /// Public so it can be unit-tested without network access.
  static OCRResult parseResponse(String body) {
    final dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      throw const OcrException('Unreadable response from OCR service.');
    }
    if (json is! Map<String, dynamic>) {
      throw const OcrException('Unexpected response from OCR service.');
    }
    if (json['IsErroredOnProcessing'] == true) {
      final msg = json['ErrorMessage'];
      final text = msg is List ? msg.join(' ') : (msg?.toString() ?? 'OCR failed.');
      throw OcrException(text);
    }
    final results = json['ParsedResults'];
    if (results is! List || results.isEmpty) {
      return const OCRResult(confidence: 0, isDemo: false);
    }
    final first = results.first;
    final text = first is Map ? (first['ParsedText']?.toString() ?? '') : '';
    return ReceiptParser.parse(text);
  }
}

/// Heuristic receipt text parser (pure Dart, no I/O).
///
/// `confidence` is NOT OCR accuracy (OCR.space doesn't return one here): it
/// is the share of the three key fields — merchant, amount, date — that
/// were found, as 0, 33, 67 or 100.
class ReceiptParser {
  ReceiptParser._();

  static final _moneyToken = RegExp(r'\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?');
  static final _decimalToken = RegExp(r'\d+\.\d{1,2}');

  static OCRResult parse(String text, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const OCRResult(confidence: 0, isDemo: false);

    final merchant = _merchant(lines);
    final amount = _amount(lines);
    final date = _date(lines, today);
    final tax = _tax(lines);
    final category = _category(lines.take(8).join(' '));

    final found = (merchant != null ? 1 : 0) + (amount != null ? 1 : 0) + (date != null ? 1 : 0);
    return OCRResult(
      merchant: merchant,
      amount: amount,
      category: category,
      date: date,
      items: const [],
      tax: tax,
      confidence: (found / 3 * 100).roundToDouble(),
      isDemo: false,
    );
  }

  // ── merchant: first plausible name line near the top ────────────────────
  static final _notMerchant = RegExp(
      r'invoice|receipt|\bbill\b|\btax\b|gstin|\bgst\b|\btel\b|phone|ph:|\bmob|cash memo|\bdate\b|welcome|thank|www\.|http|@',
      caseSensitive: false);

  static String? _merchant(List<String> lines) {
    for (final line in lines.take(6)) {
      final letters = RegExp(r'[A-Za-z]').allMatches(line).length;
      if (letters < 3 || !RegExp(r'[A-Za-z]{3,}').hasMatch(line)) continue; // needs a real word
      if (letters < line.replaceAll(' ', '').length * 0.5) continue; // mostly digits/symbols
      if (_notMerchant.hasMatch(line)) continue;
      return line.length > 40 ? line.substring(0, 40).trim() : line;
    }
    return null;
  }

  // ── amount: a "total" line, else nothing (no guessing from stray numbers) ─
  static const _skipTotals = ['sub total', 'subtotal', 'total items', 'total qty', 'total savings', 'total discount'];
  static const _strongTotals = [
    'grand total', 'net total', 'net amount', 'amount payable', 'total payable',
    'amount due', 'bill amount', 'total amount',
  ];

  static double? _amount(List<String> lines) {
    double? fromGroup(bool Function(String l) match) {
      double? found;
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i].toLowerCase();
        if (_skipTotals.any(l.contains) || !match(l)) continue;
        var v = _lastNumber(lines[i]);
        // Sometimes the number sits on the next line.
        if (v == null && i + 1 < lines.length) v = _lastNumber(lines[i + 1]);
        if (v != null) found = v; // keep the last match in the group
      }
      return found;
    }

    return fromGroup((l) => _strongTotals.any(l.contains)) ??
        fromGroup((l) => RegExp(r'\btotal\b').hasMatch(l));
  }

  static double? _lastNumber(String line) {
    final tokens = _moneyToken.allMatches(line).map((m) => m.group(0)!).toList();
    if (tokens.isEmpty) return null;
    final v = double.tryParse(tokens.last.replaceAll(',', ''));
    if (v == null || v <= 0 || v > 10000000) return null;
    return v;
  }

  // ── tax: GST/VAT lines that carry a decimal amount ───────────────────────
  static final _taxWord = RegExp(r'\b(cgst|sgst|igst|gst|vat|tax)\b', caseSensitive: false);

  static double? _tax(List<String> lines) {
    final taxLines = lines.where((l) => _taxWord.hasMatch(l) && !l.toLowerCase().contains('taxable')).toList();
    double? lastDecimal(String l) {
      final t = _decimalToken.allMatches(l).map((m) => m.group(0)!).toList();
      return t.isEmpty ? null : double.tryParse(t.last);
    }

    final totalTax = taxLines.where((l) => l.toLowerCase().contains('total')).toList();
    if (totalTax.isNotEmpty) return lastDecimal(totalTax.last);
    final values = taxLines.map(lastDecimal).whereType<double>().toList();
    if (values.isEmpty) return null;
    final sum = values.fold(0.0, (s, v) => s + v);
    return double.parse(sum.toStringAsFixed(2));
  }

  // ── date: dd/mm/yyyy (India), yyyy-mm-dd, or "14 Oct 2026" ───────────────
  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  static final _dmy = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b');
  static final _ymd = RegExp(r'\b(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})\b');
  static final _dMonY = RegExp(
      r'\b(\d{1,2})[ \-]?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[ ,\-]*(\d{2,4})\b',
      caseSensitive: false);

  static DateTime? _date(List<String> lines, DateTime today) {
    DateTime? valid(int y, int m, int d) {
      if (y < 100) y += 2000;
      if (m < 1 || m > 12 || d < 1 || d > 31) return null;
      final dt = DateTime(y, m, d);
      if (dt.month != m || dt.day != d) return null; // e.g. 31 Feb
      if (y < 2000 || dt.isAfter(today.add(const Duration(days: 1)))) return null;
      return dt;
    }

    final text = lines.join('\n');
    for (final m in _ymd.allMatches(text)) {
      final dt = valid(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
      if (dt != null) return dt;
    }
    for (final m in _dmy.allMatches(text)) {
      final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
      // Day-first by default; swap only when the second number can't be a month.
      final dt = (b > 12 && a <= 12) ? valid(y, a, b) : valid(y, b, a);
      if (dt != null) return dt;
    }
    for (final m in _dMonY.allMatches(text)) {
      final dt = valid(int.parse(m.group(3)!), _months[m.group(2)!.toLowerCase()]!, int.parse(m.group(1)!));
      if (dt != null) return dt;
    }
    return null;
  }

  // ── category: only when the header clearly says what kind of shop it is ──
  // Values are the app's own categories (AppConstants.categories).
  static final _categoryRules = <String, RegExp>{
    'Health': RegExp(r'\b(pharmacy|chemist|medical|medplus|apollo|hospital|clinic|diagnostic)', caseSensitive: false),
    'Transport': RegExp(r'\b(petrol|diesel|fuel|hpcl|bpcl|iocl|indian oil|parking|toll|uber|metro)\b', caseSensitive: false),
    'Entertainment': RegExp(r'\b(cinema|pvr|inox|multiplex|bookmyshow|movie)', caseSensitive: false),
    'Food': RegExp(r'\b(restaurant|cafe|café|bakery|pizza|burger|biryani|dhaba|sweets|canteen|supermarket|grocery|kirana|d-?mart|bigbasket)', caseSensitive: false),
    'Shopping': RegExp(r'\b(mall|fashion|apparel|retail|bazaar|myntra|lifestyle store)', caseSensitive: false),
  };

  static String? _category(String header) {
    for (final e in _categoryRules.entries) {
      if (e.value.hasMatch(header)) return e.key;
    }
    return null;
  }
}
