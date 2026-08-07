import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/battle_xp.dart';
import 'package:isekai_strategem/src/game/team_efficiency.dart';

/// Combat-v2 5.2 / 15.8: the inverse-TEG battle-XP counterweight formula.
void main() {
  test('XP bonus is inverse to grade (D richest, SSS thinnest)', () {
    expect(battleXpBonusPercentFor(TegTier.d), 75);
    expect(battleXpBonusPercentFor(TegTier.sss), 5);
    // Strictly decreasing from D up to SSS.
    final order = [
      TegTier.d,
      TegTier.c,
      TegTier.b,
      TegTier.a,
      TegTier.s,
      TegTier.ss,
      TegTier.sss,
    ];
    for (var i = 1; i < order.length; i++) {
      expect(battleXpBonusPercentFor(order[i]),
          lessThan(battleXpBonusPercentFor(order[i - 1])));
    }
  });

  test('multiplier and award apply the bonus', () {
    expect(battleXpMultiplierFor(TegTier.d), closeTo(1.75, 1e-9));
    expect(battleXpMultiplierFor(TegTier.sss), closeTo(1.05, 1e-9));
    expect(awardBattleXp(100, TegTier.d), 175);
    expect(awardBattleXp(100, TegTier.sss), 105);
  });
}
