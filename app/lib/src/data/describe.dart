import 'package:battle_engine/battle_engine.dart';

const typeLabel = <CharacterType, String>{
  CharacterType.attack: 'ATK',
  CharacterType.defense: 'DEF',
  CharacterType.support: 'SUP',
  CharacterType.unique: 'UNQ',
};

const blackTriggerTypeLabel = <BlackTriggerType, String>{
  BlackTriggerType.attack: 'ATK',
  BlackTriggerType.defense: 'DEF',
  BlackTriggerType.support: 'SUP',
  BlackTriggerType.unique: 'UNQ',
};

const skillClassLabel = <AiSkillClass, String>{
  AiSkillClass.beginner: 'Beginner',
  AiSkillClass.amateur: 'Amateur',
  AiSkillClass.intermediate: 'Intermediate',
  AiSkillClass.professional: 'Professional',
  AiSkillClass.expert: 'Expert',
};

const statLabel = <ModifiableStat, String>{
  ModifiableStat.attack: 'Attack',
  ModifiableStat.defense: 'Defense',
  ModifiableStat.armor: 'Armor',
  ModifiableStat.maxHealth: 'Max Health',
  ModifiableStat.trionAffinity: 'Trion Affinity',
  ModifiableStat.teamSpirit: 'Team Spirit',
  ModifiableStat.criticalChance: 'Critical Chance',
  ModifiableStat.fatChance: 'FAT Chance',
  ModifiableStat.statusEffectInfliction: 'Status Effect Infliction',
  ModifiableStat.statusEffectResistance: 'Status Effect Resistance',
};

String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _formatNumber(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();

/// One-paragraph player-facing description of what an active Trigger
/// does, computed from its data (mirrors the web demo's description).
String describeActiveTrigger(
  ActiveTrigger t, {
  StatusEffectCatalog? statusCatalog,
}) {
  final catalog = statusCatalog ?? StatusEffectCatalog.defaultCatalog;
  final parts = <String>[];
  final rangeWord = t.rangeTag == RangeTag.ranged ? 'Ranged' : 'Melee';
  if (t.attackSubtype == AttackSubtype.aoe) {
    parts.add('$rangeWord attack, hits all ${t.targetCount} targets at once.');
  } else if (t.attackSubtype == AttackSubtype.burst) {
    parts.add(
      '$rangeWord attack: ${t.hitsPerUse} hits split across up to ${t.targetCount} target(s).',
    );
  } else if (t.targetAffiliation == TargetAffiliation.self) {
    parts.add('Affects the user only.');
  } else if (t.targetAffiliation == TargetAffiliation.ally) {
    parts.add('$rangeWord, targets one ally.');
  } else {
    parts.add('$rangeWord attack on a single target.');
  }
  if (t.damageType != null && t.damage != null) {
    parts.add(
      '${capitalize(t.damageType!.name)} damage, avg ${t.damage!.average.round()}'
      '${t.attackSubtype == AttackSubtype.burst ? ' per hit' : ''}.',
    );
  }
  if (t.healAmount != null) {
    parts.add(
      'Heals ${t.healsCasterInstead ? 'the user' : 'the target'} for avg ${t.healAmount!.average.round()}.',
    );
  }
  if (t.inflictedStatusEffects.isNotEmpty) {
    parts.add(
      'Inflicts '
      '${t.inflictedStatusEffects.map((a) => catalog[a.statusEffectId].name).join(' + ')}.',
    );
  }
  parts.add(
    'Costs ${t.trionCost} Trion, cooldown ${t.cooldownTurns} turn${t.cooldownTurns == 1 ? '' : 's'}.',
  );
  return parts.join(' ');
}

String describePassiveEffect(PassiveEffect effect) {
  final bits = <String>[];
  if (effect.flatStatModifiers.isNotEmpty) {
    bits.add(
      effect.flatStatModifiers.entries
          .map(
            (e) =>
                '${e.value > 0 ? '+' : ''}${_formatNumber(e.value)} ${statLabel[e.key] ?? e.key.name}',
          )
          .join(', '),
    );
  }
  if (effect.statusInvulnerabilitiesGranted.isNotEmpty) {
    final catalog = StatusEffectCatalog.defaultCatalog;
    bits.add(
      'Immune to '
      '${effect.statusInvulnerabilitiesGranted.map((id) => catalog[id].name).join(', ')}',
    );
  }
  if (effect.damageResistancesGranted.isNotEmpty) {
    bits.add(
      'Resists '
      '${effect.damageResistancesGranted.map((d) => capitalize(d.name)).join(', ')} damage',
    );
  }
  return bits.isEmpty ? 'No stat effect.' : '${bits.join('. ')}.';
}

String describeTrigger(Trigger t) => switch (t) {
  ActiveTrigger a => describeActiveTrigger(a),
  PassiveTrigger p => describePassiveEffect(p.effect),
};

/// The compact "what does this do" line for ability buttons.
String triggerSummaryLine(ActiveTrigger t) {
  final catalog = StatusEffectCatalog.defaultCatalog;
  final bits = <String>[];
  if (t.damageType != null && t.damage != null) {
    bits.add('${t.damageType!.name} ${t.damage!.average.round()}');
  }
  if (t.healAmount != null) {
    bits.add(
      'heal ${t.healAmount!.average.round()}${t.healsCasterInstead ? ' (self)' : ''}',
    );
  }
  if (t.inflictedStatusEffects.isNotEmpty) {
    bits.add(
      t.inflictedStatusEffects
          .map((a) => catalog[a.statusEffectId].name)
          .join(', '),
    );
  }
  return bits.isEmpty ? 'no direct effect' : bits.join(' - ');
}

/// The ability/passive/World lines shown under a Black Trigger.
List<String> blackTriggerAbilityLines(BlackTrigger bt) => [
  for (final a in bt.activeAbilities) '${a.name}: ${describeActiveTrigger(a)}',
  for (final p in bt.passiveAbilities)
    '${p.name}: ${describePassiveEffect(p.effect)}',
  if (bt.worldAbility != null) 'World ability: ${bt.description}',
];
