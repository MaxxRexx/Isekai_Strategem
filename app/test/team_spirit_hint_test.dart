import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/widgets/pickers.dart';

void main() {
  group('teamSpiritEffectHint', () {
    test('midpoint reads neutral', () {
      expect(teamSpiritEffectHint(50), contains('neutral'));
    });

    test('below midpoint reads offense with damage and crit', () {
      final hint = teamSpiritEffectHint(0);
      expect(hint, contains('offense'));
      expect(hint, contains('dmg'));
      expect(hint, contains('crit'));
    });

    test('above midpoint reads sustain with regen and FAT', () {
      final hint = teamSpiritEffectHint(100);
      expect(hint, contains('sustain'));
      expect(hint, contains('regen'));
      expect(hint, contains('FAT'));
    });

    test('offense magnitude grows as Team Spirit drops', () {
      final near = teamSpiritEffectHint(40);
      final far = teamSpiritEffectHint(0);
      expect(near, contains('offense'));
      expect(far, contains('offense'));
      expect(near, isNot(equals(far)));
    });
  });
}
