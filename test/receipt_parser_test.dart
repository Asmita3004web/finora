import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:finora/services/ocr_service.dart';

void main() {
  final now = DateTime(2026, 10, 22);

  test('supermarket receipt: merchant, total, date, tax, category', () {
    const text = '''D-MART SUPERMARKET
Avenue Supermarts Ltd
GSTIN 29ABCDE1234F1Z5
Date: 14/10/2026  Time 18:42
Rice 5kg        450.00
Milk            56.00
Sub Total       506.00
CGST 2.5%        12.65
SGST 2.5%        12.65
TOTAL           531.30
CASH            600.00
CHANGE           68.70''';
    final r = ReceiptParser.parse(text, now: now);
    expect(r.merchant, 'D-MART SUPERMARKET');
    expect(r.amount, 531.30); // TOTAL, not Sub Total / Cash / Change
    expect(r.date, DateTime(2026, 10, 14));
    expect(r.tax, 25.30); // CGST + SGST
    expect(r.category, 'Food');
    expect(r.confidence, 100);
    expect(r.isDemo, isFalse);
  });

  test('restaurant receipt: grand total with rupee sign and thousands separator', () {
    const text = '''Barbeque Nation Restaurant
Tel 080 4455 6677
Invoice 8841   3 Sep 2026
2 x Buffet      2,200.00
Service Charge    110.00
Total GST         125.50
Grand Total   ₹ 2,435.50''';
    final r = ReceiptParser.parse(text, now: now);
    expect(r.merchant, 'Barbeque Nation Restaurant');
    expect(r.amount, 2435.50);
    expect(r.date, DateTime(2026, 9, 3));
    expect(r.tax, 125.50);
    expect(r.category, 'Food');
  });

  test('total on the next line is picked up', () {
    final r = ReceiptParser.parse('Shell Petrol Pump\nFuel 1200\nTotal\n 1,200.00', now: now);
    expect(r.amount, 1200.00);
    expect(r.category, 'Transport');
  });

  test('invalid or future dates are rejected, valid ones kept', () {
    final r = ReceiptParser.parse('Apollo Pharmacy\n12-10-26\nTOTAL 340.00\nDate: 14/10/2031', now: now);
    expect(r.date, DateTime(2026, 10, 12));
    final bad = ReceiptParser.parse('Shell Petrol Pump\nDate 31/02/2026\nTotal 500.00', now: now);
    expect(bad.date, isNull); // 31 Feb does not exist
  });

  test('nothing recognisable: fields stay null, nothing invented', () {
    final r = ReceiptParser.parse('xx 12 yy\n?? 4 5', now: now);
    expect(r.merchant, isNull);
    expect(r.amount, isNull); // no "total" line, so no guess from stray numbers
    expect(r.date, isNull);
    expect(r.tax, isNull);
    expect(r.category, isNull);
    expect(r.confidence, 0);
    expect(ReceiptParser.parse('', now: now).confidence, 0);
  });

  test('OCR.space response: success, error and empty results', () {
    final ok = jsonEncode({
      'IsErroredOnProcessing': false,
      'ParsedResults': [
        {'ParsedText': 'Cafe Coffee Day\r\n02/10/2026\r\nTOTAL 245.00'}
      ],
    });
    final r = OcrSpaceService.parseResponse(ok);
    expect(r.amount, 245.00);
    expect(r.merchant, 'Cafe Coffee Day');

    final err = jsonEncode({
      'IsErroredOnProcessing': true,
      'ErrorMessage': ['File size exceeds limit'],
    });
    expect(() => OcrSpaceService.parseResponse(err), throwsA(isA<OcrException>()));

    expect(OcrSpaceService.parseResponse(jsonEncode({'ParsedResults': []})).confidence, 0);
    expect(() => OcrSpaceService.parseResponse('not json'), throwsA(isA<OcrException>()));
  });

  test('oversized image is rejected before any network call', () async {
    final service = OcrSpaceService(apiKey: 'test');
    await expectLater(service.scanReceipt(List.filled(OcrSpaceService.maxBytes + 1, 0)),
        throwsA(isA<OcrException>()));
  });
}
