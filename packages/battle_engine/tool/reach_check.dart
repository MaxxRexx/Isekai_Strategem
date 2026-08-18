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

  print('\nCLAIM 3: can healing take a character above 100?');
  final def = StatusEffectCatalog.defaultCatalog['rallied'];
  print('  Rallied: ${def.flatStatModifiers}, '
      'lasts ${def.defaultDurationTurns} turns');
  final c = CharacterBattleState(
    Character(
      id: 'x',
      name: 'X',
      type: CharacterType.support,
      baseStats: const Stats(
        maxHealth: 100,
        attack: 8,
        defense: 6,
        armor: 0,
        trionCapacity: 100,
        trionAffinity: 8,
        teamSpirit: 50,
        criticalChance: 5,
        fatChance: 10,
        statusEffectInfliction: 5,
        statusEffectResistance: 5,
      ),
    ),
  );
  print('  base max health: ${c.character.baseStats.maxHealth}');
  print('  effective max, no Rallied: ${c.effectiveStats().maxHealth}');
  StatusEffectEngine().apply(c, 'rallied');
  print('  effective max, Rallied up: ${c.effectiveStats().maxHealth}');
  print('  healing clamps to the effective max, so with Rallied a character');
  print('  can currently sit above their base 100.');
}
