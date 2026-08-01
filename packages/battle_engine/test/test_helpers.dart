import 'dart:math';

import 'package:battle_engine/battle_engine.dart';

/// A [Random] that returns a fixed sequence of `nextInt` results, so a test
/// can force exact die outcomes (e.g. an exact tie, or a specific natural
/// roll) that real dice can't be relied on to produce on demand.
class SequenceRandom implements Random {
  final List<int> _sequence;
  int _index = 0;
  SequenceRandom(this._sequence);

  @override
  int nextInt(int max) => _sequence[_index++] % max;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}

/// A [Random] that always returns the same `nextInt` result, regardless of
/// how many times it's called. Useful for forcing a specific die face
/// (e.g. `FixedRandom(19)` always rolls a natural 20 on a d20) without
/// needing to know exactly how many rolls a call will consume. The value is
/// taken modulo [max] so it always satisfies `Random.nextInt`'s contract
/// of returning a value in `[0, max)`.
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

Stats testStats({
  int trionCapacity = 100,
  int trionAffinity = 10,
  int teamSpirit = 50,
  double criticalChance = 5,
  double fatChance = 10,
  int armor = 5,
  int maxHealth = 100,
  int attack = 10,
  int defense = 10,
  int statusEffectInfliction = 10,
  int statusEffectResistance = 2,
}) {
  return Stats(
    trionCapacity: trionCapacity,
    trionAffinity: trionAffinity,
    teamSpirit: teamSpirit,
    criticalChance: criticalChance,
    fatChance: fatChance,
    armor: armor,
    maxHealth: maxHealth,
    attack: attack,
    defense: defense,
    statusEffectInfliction: statusEffectInfliction,
    statusEffectResistance: statusEffectResistance,
  );
}

Character testCharacter({
  String id = 'char-1',
  String name = 'Test Character',
  CharacterType type = CharacterType.attack,
  Stats? stats,
  Set<DamageType> damageResistances = const {},
  Set<String> statusInvulnerabilities = const {},
  CharacterPerk? perk,
}) {
  return Character(
    id: id,
    name: name,
    type: type,
    baseStats: stats ?? testStats(),
    damageResistances: damageResistances,
    statusInvulnerabilities: statusInvulnerabilities,
    perk: perk,
  );
}

ActiveTrigger testTrigger({
  String id = 'trigger-1',
  String name = 'Test Trigger',
  TriggerCategory category = TriggerCategory.attacker,
  int equipCost = 10,
  int trionCost = 5,
  int cooldownTurns = 2,
  OriginTag originTag = OriginTag.physical,
  RangeTag rangeTag = RangeTag.melee,
  AttackType attackType = AttackType.melee,
  AttackSubtype attackSubtype = AttackSubtype.single,
  int hitsPerUse = 1,
  int targetCount = 1,
  TargetAffiliation targetAffiliation = TargetAffiliation.opponent,
  DamageType? damageType,
  DiceExpression? damage,
  bool includeDamage = true,
  DiceExpression? healAmount,
  bool healsCasterInstead = false,
  List<StatusEffectApplication> inflictedStatusEffects = const [],
  ReactiveKind? armsReactive,
  int? armsReactiveDefaultTurns,
}) {
  return ActiveTrigger(
    id: id,
    name: name,
    category: category,
    equipCost: equipCost,
    trionCost: trionCost,
    cooldownTurns: cooldownTurns,
    originTag: originTag,
    rangeTag: rangeTag,
    attackType: attackType,
    attackSubtype: attackSubtype,
    hitsPerUse: hitsPerUse,
    targetCount: targetCount,
    targetAffiliation: targetAffiliation,
    damageType: includeDamage ? (damageType ?? DamageType.slashing) : null,
    damage: includeDamage ? (damage ?? const DiceExpression(1, 6)) : null,
    healAmount: healAmount,
    healsCasterInstead: healsCasterInstead,
    inflictedStatusEffects: inflictedStatusEffects,
    armsReactive: armsReactive,
    armsReactiveDefaultTurns: armsReactiveDefaultTurns,
  );
}

PassiveTrigger testPassiveTrigger({
  String id = 'passive-trigger-1',
  String name = 'Test Passive Trigger',
  TriggerCategory category = TriggerCategory.optional,
  int equipCost = 10,
  PassiveEffect effect = const PassiveEffect(),
}) {
  return PassiveTrigger(
    id: id,
    name: name,
    category: category,
    equipCost: equipCost,
    effect: effect,
  );
}
