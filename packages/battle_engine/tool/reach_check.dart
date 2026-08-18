import 'package:battle_engine/battle_engine.dart';

/// Direct checks of three claims, against the live rules with no screening.
void main() {
  const lines = BattlePosition.values;

  print('CLAIM 1: a Long Range wielder at the Back reaches every enemy line.');
  for (final me in lines) {
    final row = lines.map((them) {
      final d = BattleDistance.betweenEnemies(me, them);
      return '${them.label}=d$d ${RangeTag.long.reaches(d) ? 'HIT ' : 'miss'}';
    }).join('  ');
    print('  wielder at ${me.label.padRight(7)} $row');
  }

  print('\nCLAIM 2: with Close widened to 0-2, is any line safe from a Close');
  print('attacker standing on their front line?');
  for (final me in lines) {
    final d = BattleDistance.betweenEnemies(me, BattlePosition.front);
    final widened = d >= 0 && d <= 2;
    final current = RangeTag.close.reaches(d);
    print('  I stand at ${me.label.padRight(7)} d$d  '
        'Close 0-1: ${current ? 'HIT' : 'safe'}   '
        'Close 0-2: ${widened ? 'HIT' : 'safe'}');
  }

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
