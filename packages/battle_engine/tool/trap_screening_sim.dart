import 'dart:math';

import 'package:battle_engine/battle_engine.dart';

/// Q1 for item 1b: does a screen block a trap?
///
/// Runs the two traps the game actually has, on a real Battle with the real
/// roster and deterministic dice, and reports whether each one fires.
///
/// Run it against the engine as it stands to see answer **#B** (the fire-time
/// reach check ignores screens, which is also today's behaviour), and against
/// an engine whose `_trapStillReaches` adds the holder's screens to see answer
/// **#A**. Everything else is identical, so any difference in the verdicts is
/// the whole of what Q1 decides.
///
/// The two traps, both placed on an enemy:
///
///  - **Deadfall** (`paradox_shard_deadfall`), a Paradox Shard Black Trigger
///    ability. Long Range, 2 to 4. If the trapped enemy uses a damaging
///    ability, it is countered and they take 4d8+16 Force instead. This is the
///    only reactive in the game whose reach is re-checked when it fires.
///  - **Death Ledger** (`death_ledger`), an ordinary Trigger. Mid Range, 1 to
///    3. If the trapped enemy uses an area attack, it is nullified. Its reach
///    is never re-checked, so it fires from anywhere.
///
/// Note what is *not* in question: planting a trap goes through `canTarget`,
/// so the arm-time check counts screens under either answer. Q1 is only about
/// the re-check when the trap fires.

/// Always rolls the top of the die, so nothing here depends on luck.
class FixedRandom implements Random {
  final int value;
  const FixedRandom(this.value);
  @override
  int nextInt(int max) => value % max;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

TurnEngine deterministicEngine() => TurnEngine(
      combatEngine: CombatEngine(diceRoller: DiceRoller(const FixedRandom(19))),
      statusEffectEngine:
          StatusEffectEngine(diceRoller: DiceRoller(const FixedRandom(19))),
    );

const ourSquad = ['kaito_reyes', 'vela_ashworth', 'dross'];
const theirSquad = ['marren_osei', 'ilona_vance', 'bastian_cole'];

/// Their sniper, the one both traps get planted on.
const sniper = 'bastian_cole';

Battle freshBattle() {
  final roster = CharacterRoster.defaultRoster;
  return Battle(
    teamA: Team(
      id: 'ours',
      characters: [for (final id in ourSquad) roster[id]],
      trionPool: TrionPool(current: 500, cap: 500),
    ),
    teamB: Team(
      id: 'theirs',
      characters: [for (final id in theirSquad) roster[id]],
      trionPool: TrionPool(current: 500, cap: 500),
    ),
    turnEngine: deterministicEngine(),
  );
}

ActiveTrigger trigger(String id) =>
    TriggerCatalog.defaultCatalog[id] as ActiveTrigger;

ActiveTrigger get deadfall =>
    BlackTriggerCatalog.defaultCatalog['paradox_shard']
        .activeAbilities
        .firstWhere((a) => a.id == 'paradox_shard_deadfall');

/// Screens in front of [targetId], counting only their own living squadmates.
int screensInFrontOf(Battle battle, String targetId, List<String> squad) {
  final target = battle.states[targetId]!;
  return squad
      .where((id) => id != targetId)
      .map((id) => battle.states[id]!)
      .where((s) => s.isAlive && s.position.step < target.position.step)
      .length;
}

String formation(Battle battle, List<String> squad) => squad.map((id) {
      final s = battle.states[id]!;
      return '${s.character.name.split(' ').first}@${s.position.label}'
          '${s.isAlive ? '' : ' down'}';
    }).join(', ');

void setLines(Battle battle, Map<String, BattlePosition> lines) {
  lines.forEach((id, line) => battle.states[id]!.position = line);
}

bool stillArmed(Battle battle, String holderId, ReactiveKind kind) => battle
    .states[holderId]!
    .reactiveEffects
    .any((r) => r.kind == kind);

void heading(String text) {
  print('\n${'-' * 76}');
  print(text);
  print('-' * 76);
}

void line(String label, Object value) => print('  ${label.padRight(36)}$value');

/// The two numbers Q1 chooses between, for a trap laid from [armedStep] onto
/// [holderId].
void reportDistances(Battle battle, int armedStep, String holderId,
    List<String> holderSquad, RangeTag band) {
  final holderStep = battle.states[holderId]!.position.step;
  final screens = screensInFrontOf(battle, holderId, holderSquad);
  final raw = armedStep + holderStep;
  line('screens in front of the holder', screens);
  line('#B  raw distance',
      '$raw   ${band.reaches(raw) ? 'inside' : 'OUTSIDE'} ${band.label} ${band.windowLabel}');
  line('#A  screened distance',
      '${raw + screens}   ${band.reaches(raw + screens) ? 'inside' : 'OUTSIDE'} ${band.label} ${band.windowLabel}');
}

// ---------------------------------------------------------------------------
// Example 1: Deadfall, and a screen that arrives after the trap is planted.
// ---------------------------------------------------------------------------

void example1() {
  heading('EXAMPLE 1   Deadfall, Long Range 2 to 4\n'
      'Their squad is camped on their back line, so nobody screens anybody.\n'
      'I plant Deadfall on their sniper from my own back line. Then two of\n'
      'their squad walk forward and end up standing in front of the sniper.');

  final battle = freshBattle();
  setLines(battle, {
    for (final id in ourSquad) id: BattlePosition.back,
    for (final id in theirSquad) id: BattlePosition.back,
  });

  final caster = battle.states['dross']!;
  final target = battle.states[sniper]!;
  final armedStep = caster.position.step;

  print('\nTURN 1   I plant the trap');
  line('my squad', formation(battle, ourSquad));
  line('their squad', formation(battle, theirSquad));
  reportDistances(battle, armedStep, sniper, theirSquad, deadfall.rangeTag);

  final canArm = battle.turnEngine.canTarget(caster, target, trigger: deadfall);
  line('can I plant it?', canArm ? 'yes' : 'NO, out of range');
  if (!canArm) return;

  battle.turnEngine.resolveAbilityUse(
    attacker: caster,
    trigger: deadfall,
    targets: [target],
  );
  line('trap armed on the sniper?',
      stillArmed(battle, sniper, ReactiveKind.trapOnAction) ? 'yes' : 'no');

  print('\nTURN 2   Two of their squad step up in front of the sniper');
  setLines(battle, {
    'marren_osei': BattlePosition.front,
    'ilona_vance': BattlePosition.front,
  });
  line('their squad', formation(battle, theirSquad));
  reportDistances(battle, armedStep, sniper, theirSquad, deadfall.rangeTag);
  print('      Nothing about the trap changed. Only their formation did.');

  print('\nTURN 3   The trapped sniper attacks, which is what Deadfall waits for');
  final shot = trigger('longshot');
  final victim = battle.states['kaito_reyes']!;
  line('the sniper uses',
      '${shot.name} (${shot.rangeTag.label} ${shot.rangeTag.windowLabel})');
  final shotIsLegal =
      battle.turnEngine.canTarget(target, victim, trigger: shot);
  line('their shot is in range of Kaito?',
      shotIsLegal ? 'yes, so nothing is confounded' : 'NO, bad fixture');

  final sniperBefore = target.currentHealth;
  final victimBefore = victim.currentHealth;
  battle.turnEngine.resolveAbilityUse(
    attacker: target,
    trigger: shot,
    targets: [victim],
  );

  final trapFired = target.currentHealth < sniperBefore;
  final shotLanded = victim.currentHealth < victimBefore;

  line('sniper took trap damage?',
      trapFired ? 'YES, ${sniperBefore - target.currentHealth}' : 'no');
  line('their shot landed on Kaito?',
      shotLanded ? 'yes, ${victimBefore - victim.currentHealth}' : 'no');
  line('trap still armed?',
      stillArmed(battle, sniper, ReactiveKind.trapOnAction)
          ? 'yes, unspent'
          : 'no, spent');
  print('\n  >>> The trap ${trapFired ? 'FIRED' : 'DID NOT FIRE'}.');
}

// ---------------------------------------------------------------------------
// Example 2: Death Ledger, the trap whose reach is never checked at all.
// ---------------------------------------------------------------------------

void example2() {
  heading('EXAMPLE 2   Death Ledger, Mid Range 1 to 3\n'
      'The same story as example 1, with the other trap and the other band.\n'
      'They are camped, I plant Death Ledger on the sniper from my middle\n'
      'line, then two of them step up and screen the sniper two deep.');

  final battle = freshBattle();
  setLines(battle, {
    'kaito_reyes': BattlePosition.front,
    'vela_ashworth': BattlePosition.front,
    'dross': BattlePosition.middle,
    for (final id in theirSquad) id: BattlePosition.back,
  });

  final ledger = trigger('death_ledger');
  final caster = battle.states['dross']!;
  final target = battle.states[sniper]!;
  final armedStep = caster.position.step;

  print('\nTURN 1   I plant the trap');
  line('my squad', formation(battle, ourSquad));
  line('their squad', formation(battle, theirSquad));
  reportDistances(battle, armedStep, sniper, theirSquad, ledger.rangeTag);

  final canArm = battle.turnEngine.canTarget(caster, target, trigger: ledger);
  line('can I plant it?', canArm ? 'yes' : 'NO, out of range');
  if (!canArm) return;

  battle.turnEngine.resolveAbilityUse(
    attacker: caster,
    trigger: ledger,
    targets: [target],
  );
  line('trap armed on the sniper?',
      stillArmed(battle, sniper, ReactiveKind.nullifyAoe) ? 'yes' : 'no');

  print('\nTURN 2   Two of their squad step up in front of the sniper');
  setLines(battle, {
    'marren_osei': BattlePosition.front,
    'ilona_vance': BattlePosition.front,
  });
  line('their squad', formation(battle, theirSquad));
  reportDistances(battle, armedStep, sniper, theirSquad, ledger.rangeTag);
  print('      Exactly the divergence example 1 had: #B keeps the trap in');
  print('      band, #A pushes it out. Watch what the engine does with that.');

  print('\nTURN 3   The trapped sniper uses an area attack');
  final blast = trigger('frag_grenade');
  line('the sniper uses',
      '${blast.name} (${blast.rangeTag.label} ${blast.rangeTag.windowLabel}, area)');
  final victims = [for (final id in ourSquad) battle.states[id]!];
  final legalVictims = victims
      .where((v) => battle.turnEngine.canTarget(target, v, trigger: blast))
      .toList();
  line('their blast has legal targets?',
      legalVictims.isEmpty ? 'NO, bad fixture' : '${legalVictims.length} of 3');
  if (legalVictims.isEmpty) return;

  final before = {for (final v in victims) v.character.id: v.currentHealth};
  final result = battle.turnEngine.resolveAbilityUse(
    attacker: target,
    trigger: blast,
    targets: victims,
  );
  final anyoneHurt =
      victims.any((v) => v.currentHealth < before[v.character.id]!);

  line('their blast hit anybody?', anyoneHurt ? 'yes' : 'no');
  line('targets it resolved against', result.targetResults.length);
  line('trap still armed?',
      stillArmed(battle, sniper, ReactiveKind.nullifyAoe)
          ? 'yes, unspent'
          : 'no, spent');
  print('\n  >>> The trap ${anyoneHurt ? 'DID NOT FIRE' : 'FIRED'}.');
  print('      Death Ledger never consults its recorded band at all, so the');
  print('      answer to Q1 does not reach it. Only Deadfall asks.');
}

void main() {
  print('Q1  Does a screen block a trap?');
  print('The two enemy-placed traps the game has, on a real Battle with the');
  print('real roster. Planting is screened under either answer; only the');
  print('re-check when the trap fires is in question.');
  example1();
  example2();
  print('');
}
