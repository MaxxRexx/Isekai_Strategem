// Measures the live baselines item #3's Status Point scale has to be
// calibrated against, by playing real AI-vs-AI battles rather than reading
// the catalog.
//
//   dart run tool/sptv_baseline.dart [--seed N] [--battles N]
//
// SP prices an effect in damage-equivalent terms, so it needs to know what a
// point of damage-equivalent actually buys in a played battle: how much
// damage one action lands, how many attacks a character makes and takes per
// turn, and how often a hostile status rider gets through. Every one of those
// is lower than the catalog's face value, and pricing off face value is how
// a status rider ends up costing the same as the damage it is bolted to.
import 'dart:math';

import 'package:battle_engine/battle_engine.dart';

import 'balance_report.dart' show buildBattleState;

class _Squad {
  final Team team;
  final Map<String, CharacterBattleState> states;
  final Map<String, List<ActiveTrigger>> equipped;
  const _Squad(this.team, this.states, this.equipped);
}

_Squad drafted(String teamId, List<String> ids, AiProfile profile) {
  const builder = LoadoutBuilder();
  final characters = ids.map((id) => CharacterRoster.defaultRoster[id]).toList();
  final states = <String, CharacterBattleState>{};
  final equipped = <String, List<ActiveTrigger>>{};
  for (final character in characters) {
    final loadout = builder.build(
      character,
      activeTriggerPool: TriggerCatalog.defaultCatalog.activeTriggers,
      passiveTriggerPool: TriggerCatalog.defaultCatalog.passiveTriggers,
      blackTriggerPool: BlackTriggerCatalog.defaultCatalog.all,
      profile: profile,
    );
    states[character.id] = buildBattleState(character, loadout);
    equipped[character.id] =
        loadout.triggers.whereType<ActiveTrigger>().toList();
  }
  return _Squad(Team(id: teamId, characters: characters), states, equipped);
}

String f(num v, [int places = 2]) => v.toStringAsFixed(places);

void main(List<String> args) {
  var seed = 20260814;
  var battles = 200;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--seed') seed = int.parse(args[i + 1]);
    if (args[i] == '--battles') battles = int.parse(args[i + 1]);
  }

  final roster = CharacterRoster.defaultRoster.all.map((c) => c.id).toList();
  final profiles = AiProfile.all;
  final random = Random(seed);

  var teamTurns = 0;
  var livingAtTurnStart = 0;
  var abilityUses = 0;
  var damagingUses = 0;
  var damageLanded = 0;
  var attackRolls = 0;
  var attackHits = 0;
  var riderAttempts = 0;
  var riderLanded = 0;


  final catalog = TriggerCatalog.defaultCatalog;

  for (var i = 0; i < battles; i++) {
    final pool = [...roster]..shuffle(random);
    final aProfile = profiles[random.nextInt(profiles.length)];
    final bProfile = profiles[random.nextInt(profiles.length)];
    final a = drafted('team-a', pool.take(3).toList(), aProfile);
    final b = drafted('team-b', pool.skip(3).take(3).toList(), bProfile);
    final dice = Random(seed * 1000003 + i);
    final battle = Battle(
      teamA: a.team,
      teamB: b.team,
      states: {...a.states, ...b.states},
      turnEngine: TurnEngine(
        combatEngine: CombatEngine(diceRoller: DiceRoller(dice)),
        statusEffectEngine: StatusEffectEngine(diceRoller: DiceRoller(dice)),
        trionGainEngine: TrionGainEngine(diceRoller: DiceRoller(dice)),
        fatEngine: FatEngine(diceRoller: DiceRoller(dice)),
      ),
    );
    final aiA = ProfileDrivenAi(aProfile, random: dice);
    final aiB = ProfileDrivenAi(bProfile, random: dice);

    for (var turn = 0; turn < 400; turn++) {
      if (battle.isOver) break;
      final active = battle.isTeamATurn ? a : b;
      final ai = battle.isTeamATurn ? aiA : aiB;
      battle.startTurn(equippedActiveTriggers: active.equipped);
      if (battle.isOver) break;

      teamTurns++;
      livingAtTurnStart +=
          active.states.values.where((s) => s.isAlive).length;

      final results = ai.takeTurn(battle,
          equippedActiveTriggers: active.equipped);
      for (final result in results) {
        abilityUses++;
        final trigger = catalog.contains(result.useResult.triggerId)
            ? catalog[result.useResult.triggerId]
            : null;
        final active0 = trigger is ActiveTrigger ? trigger : null;
        if (active0 != null &&
            active0.damage != null &&
            active0.targetAffiliation == TargetAffiliation.opponent) {
          damagingUses++;
        }
        for (final target in result.useResult.targetResults) {
          damageLanded += target.totalDamageDealt;
          for (final roll in target.attackRolls) {
            attackRolls++;
            if (roll.isHit) attackHits++;
          }
          if (active0 != null &&
              active0.targetAffiliation == TargetAffiliation.opponent &&
              active0.inflictedStatusEffects.isNotEmpty) {
            final hit = target.attackRolls.any((r) => r.isHit);
            riderAttempts += active0.inflictedStatusEffects.length;
            if (hit) {
              riderLanded += target.statusEffectsApplied
                  .where((id) => active0.inflictedStatusEffects
                      .any((s) => s.statusEffectId == id))
                  .length;
            }
          }
        }
      }
      if (battle.isOver) break;
      battle.endTurn();
    }
  }

  final charTurns = livingAtTurnStart;
  print('== SPTV baselines, $battles battles, seed $seed ==');
  print('');
  print('Team turns played            $teamTurns');
  print('Living character-turns       $charTurns');
  print('');
  print('-- what one action is worth --');
  print('  ability uses                 $abilityUses '
      '(${f(abilityUses / charTurns)} per living character-turn)');
  print('  of those, damaging           $damagingUses '
      '(${f(100 * damagingUses / abilityUses, 1)}% of uses)');
  print('  damage landed                $damageLanded');
  print('  per damaging use             ${f(damageLanded / damagingUses, 1)}'
      '   <-- what an attack action actually buys');
  print('  per living character-turn    ${f(damageLanded / charTurns, 1)}');
  print('');
  print('-- how often a character is in the firing line --');
  print('  attack rolls made            $attackRolls, '
      '${f(attackHits / attackRolls * 100, 1)}% landed');
  print('  attack rolls per char-turn   ${f(attackRolls / charTurns)}');
  print('  damage taken per char-turn   ${f(damageLanded / charTurns, 1)}'
      '   <-- what a point of damage reduction is worth per turn');
  print('');
  print('-- hostile status riders --');
  print('  attempted                    $riderAttempts');
  print('  landed                       $riderLanded '
      '(${f(100 * riderLanded / riderAttempts, 1)}%)'
      '   <-- attack must hit, then win the infliction contest');
  print('');
}
