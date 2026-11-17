import 'package:flutter_test/flutter_test.dart';
import 'package:kusina/domain/models/stock.dart';
import 'package:kusina/domain/rules/stock_rules.dart';

void main() {
  group('legal transitions', () {
    test('initial is unknown -> any recorded status', () {
      expect(
        StockRules.isLegalTransition(
          reason: StockReason.initial,
          from: StockStatus.unknown,
          to: StockStatus.have,
        ),
        isTrue,
      );
      expect(
        StockRules.isLegalTransition(
          reason: StockReason.initial,
          from: StockStatus.have,
          to: StockStatus.low,
        ),
        isFalse,
      );
    });

    test('restock only ends in have', () {
      for (final from in <StockStatus>[
        StockStatus.unknown,
        StockStatus.out,
        StockStatus.low,
      ]) {
        expect(
          StockRules.isLegalTransition(
            reason: StockReason.restock,
            from: from,
            to: StockStatus.have,
          ),
          isTrue,
          reason: 'restock ${from.wireCode} -> have',
        );
      }
      expect(
        StockRules.isLegalTransition(
          reason: StockReason.restock,
          from: StockStatus.have,
          to: StockStatus.low,
        ),
        isFalse,
      );
    });

    test('used_some ends in low from have/unknown only', () {
      expect(
        StockRules.isLegalTransition(
          reason: StockReason.usedSome,
          from: StockStatus.have,
          to: StockStatus.low,
        ),
        isTrue,
      );
      expect(
        StockRules.isLegalTransition(
          reason: StockReason.usedSome,
          from: StockStatus.out,
          to: StockStatus.low,
        ),
        isFalse,
      );
    });

    test('used_up ends in out, waste cannot start from unknown', () {
      expect(
        StockRules.isLegalTransition(
          reason: StockReason.usedUp,
          from: StockStatus.unknown,
          to: StockStatus.out,
        ),
        isTrue,
      );
      expect(
        StockRules.isLegalTransition(
          reason: StockReason.waste,
          from: StockStatus.unknown,
          to: StockStatus.out,
        ),
        isFalse,
      );
    });

    test('no reason may record a no-op', () {
      for (final reason in StockReason.values) {
        expect(
          StockRules.isLegalTransition(
            reason: reason,
            from: StockStatus.have,
            to: StockStatus.have,
          ),
          isFalse,
          reason: '${reason.wireCode} no-op',
        );
      }
    });

    test('correction is any -> any except a no-op', () {
      expect(
        StockRules.isLegalTransition(
          reason: StockReason.correction,
          from: StockStatus.out,
          to: StockStatus.have,
        ),
        isTrue,
      );
    });
  });

  group('manual-edit reason mapping', () {
    test('a no-op maps to null so nothing is written', () {
      expect(
        StockRules.reasonForManualEdit(
          from: StockStatus.have,
          to: StockStatus.have,
        ),
        isNull,
      );
    });

    test('the first record uses initial', () {
      expect(
        StockRules.reasonForManualEdit(
          from: StockStatus.unknown,
          to: StockStatus.have,
          isFirstRecord: true,
        ),
        StockReason.initial,
      );
    });

    test('later taps use the domain reason', () {
      expect(
        StockRules.reasonForManualEdit(
          from: StockStatus.have,
          to: StockStatus.low,
        ),
        StockReason.usedSome,
      );
      expect(
        StockRules.reasonForManualEdit(
          from: StockStatus.low,
          to: StockStatus.have,
        ),
        StockReason.restock,
      );
      expect(
        StockRules.reasonForManualEdit(
          from: StockStatus.have,
          to: StockStatus.out,
        ),
        StockReason.usedUp,
      );
      expect(
        StockRules.reasonForManualEdit(
          from: StockStatus.out,
          to: StockStatus.have,
        ),
        StockReason.restock,
      );
    });

    test('impossible transitions fall back to correction', () {
      expect(
        StockRules.reasonForManualEdit(
          from: StockStatus.out,
          to: StockStatus.low,
        ),
        StockReason.correction,
      );
      expect(
        StockRules.reasonForManualEdit(
          from: StockStatus.have,
          to: StockStatus.unknown,
        ),
        StockReason.correction,
      );
    });

    test('every mapped reason is legal for its transition', () {
      for (final from in StockStatus.values) {
        for (final to in StockStatus.values) {
          if (from == to) {
            continue;
          }
          final reason = StockRules.reasonForManualEdit(from: from, to: to);
          expect(
            reason,
            isNotNull,
            reason: '${from.wireCode} -> ${to.wireCode}',
          );
          expect(
            StockRules.isLegalTransition(reason: reason!, from: from, to: to),
            isTrue,
            reason:
                '${reason.wireCode} must be legal for '
                '${from.wireCode} -> ${to.wireCode}',
          );
        }
      }
    });
  });
}
