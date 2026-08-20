import 'package:battle_engine/battle_engine.dart';

/// Direct checks of three claims against the live rules, screening included.
///
/// Claims 1 and 2 were written while item 1b was still a proposal, to argue
/// for widening Close Range. Both halves are built now, so they check the
/// rules as they stand rather than comparing candidates.
void main() {
  const lines = BattlePosition.values;
  const unscreened = <BattlePosition>[];

  print('CLAIM 1: a Long Range wielder at the Back reaches every enemy line,');
  print('so long as nobody is screening the target.');
  for (final me in lines) {
    final row = lines.map((them) {
      final d = BattleDistance.betweenEnemies(me, them,
          targetSquad: unscreened);
      return '${them.label}=d$d ${RangeTag.long.reaches(d) ? 'HIT ' : 'miss'}';
    }).join('  ');
    print('  wielder at ${me.label.padRight(7)} $row');
  }

  print('\nCLAIM 2: with Close at ${RangeTag.close.windowLabel}, which enemy');
  print('lines are safe from a Close attacker, and what does screening buy?');
  for (final them in lines) {
    final row = <String>[];
    for (var screens = 0; screens <= 2; screens++) {
      // Whether ANY of my lines can bring a Close ability to bear on them.
      final reachable = lines.any((me) {
        final squad = [
          for (var i = 0; i < screens; i++) BattlePosition.front,
        ];
        // A target on the front line can never be screened, since nothing
        // stands in front of it.
        if (them == BattlePosition.front && screens > 0) return false;
        return RangeTag.close.reaches(
            BattleDistance.betweenEnemies(me, them, targetSquad: squad));
      });
      final possible = !(them == BattlePosition.front && screens > 0) &&
          !(them == BattlePosition.middle && screens > 2);
      row.add(possible
          ? '$screens screens: ${reachable ? 'reachable' : 'SAFE     '}'
          : '$screens screens: n/a      ');
    }
    print('  their ${them.label.padRight(7)} ${row.join('  ')}');
  }
  print('  A front-line target always has zero screens, so no squad can put');
  print('  its whole formation out of a Close build\'s reach.');

  print('\nCLAIM 3: can any status raise maximum health, and so let healing');
  print('take a character above their base maximum?');
  final raisers = StatusEffectCatalog.defaultCatalog.all
      .where((d) => d.flatStatModifiers.containsKey(ModifiableStat.maxHealth))
      .toList();
  if (raisers.isEmpty) {
    print('  No. Nothing in the catalogue modifies maximum health, so the');
    print('  heal clamp can never exceed the base 100.');
  } else {
    for (final d in raisers) {
      print('  ${d.name}: ${d.flatStatModifiers[ModifiableStat.maxHealth]} '
          'max health, which lets healing exceed the base maximum.');
    }
  }
}
