import 'package:flutter_test/flutter_test.dart';
import 'package:om_events/app/core/utils/om_validators.dart';

void main() {
  group('OmValidators.phone', () {
    test('accepts a plain 10-digit Indian mobile', () {
      expect(OmValidators.phone('9876543210'), isNull);
      expect(OmValidators.phone('6123456789'), isNull);
    });

    test('accepts 91-prefixed and +91-prefixed numbers', () {
      expect(OmValidators.phone('919876543210'), isNull);
      expect(OmValidators.phone('+919876543210'), isNull);
      expect(OmValidators.phone('+91 98765-43210'), isNull);
    });

    test('rejects wrong length, leading digit and malformed prefixes', () {
      expect(OmValidators.phone('987654321'), isNotNull);
      expect(OmValidators.phone('98765432101'), isNotNull);
      expect(OmValidators.phone('5876543210'), isNotNull);
      expect(OmValidators.phone('+19876543210'), isNotNull);
    });

    test('rejects an empty value', () {
      expect(OmValidators.phone(''), 'Mobile number is required');
    });
  });
}
