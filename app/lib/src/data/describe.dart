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

/// How long a status effect lasts, in the only terms a player can act on:
/// their own turns.
///
/// The engine ticks an effect down at the **start of its holder's turn**, and
/// the queue resolves buffs before attacks, so an effect applied on a turn is
/// live for the rest of that turn's resolution and through the opponent's
/// answer, and is then decremented when its holder's next turn begins. A
/// 1-turn effect is therefore gone before its holder acts again, which is
/// exactly the thing a bare "1 turn" fails to tell anyone.
///
/// [onSelf] switches the possessive, since the turns being counted are the
/// holder's, and the holder is the target for a debuff.
String describeStatusDuration(int? turns, {required bool onSelf}) {
  if (turns == null) return 'Lasts until it is removed.';
  final whose = onSelf ? 'your' : 'their';
  if (turns <= 1) {
    return 'Active this turn only. It wears off when $whose next turn begins.';
  }
  final more = turns - 1;
  return 'Active this turn and $whose next '
      '${more == 1 ? 'turn' : '$more turns'}.';
}

/// What a status effect actually does, in plain terms, followed by how long
/// it lasts. This is the line the battle interface shows for a status badge,
/// and the line an ability's description borrows when it inflicts one.
///
/// Deliberately short: the full prose pass over all 63 effects is its own
/// item. This states the mechanical effect and the duration, which are the two
/// things a player cannot work out by looking.
String describeStatusEffect(
  StatusEffectDefinition def, {
  required bool onSelf,
}) {
  // Every clause is written to follow "You" or "They", so it stays a base-form
  // verb ("deal", not "deals") and the two subjects share one phrasing.
  final whose = onSelf ? 'your' : 'their';
  final bits = <String>[];

  if (def.preventsActions) bits.add('cannot act at all');
  if (def.preventsReposition) bits.add('cannot move off this line');
  if (def.preventsTargeting) bits.add('cannot be targeted');
  if (def.preventsHealing) bits.add('cannot be healed');
  if (def.preventsAllyInteraction) bits.add('cannot be helped by allies');
  if (def.cannotTargetSource) bits.add('cannot target whoever applied this');
  if (def.forcesNextAttackMiss) bits.add('miss the next attack outright');
  if (def.forcesRepetitionOfLastAbility) {
    bits.add('must repeat the last ability used');
  }
  if (def.locksRandomAbilityEachTurn) {
    bits.add('lose the use of one random ability each turn');
  }
  if (def.rangedTargetsReducedByOne) {
    bits.add('hit one fewer target with Mid and Long Range attacks');
  }
  if (def.sourceHasAdvantageAgainstTarget) {
    bits.add('are attacked at an advantage by whoever applied this');
  }
  if (def.outgoingDamageMultiplier != null) {
    final pct = ((def.outgoingDamageMultiplier! - 1) * 100).round();
    bits.add('deal ${pct >= 0 ? '$pct% more' : '${-pct}% less'} damage');
  }
  if (def.allDamageTakenMultiplier != null) {
    final pct = ((def.allDamageTakenMultiplier! - 1) * 100).round();
    bits.add('take ${pct >= 0 ? '$pct% more' : '${-pct}% less'} damage');
  }
  if (def.trionCostMultiplier != null) {
    final pct = ((def.trionCostMultiplier! - 1) * 100).round();
    bits.add('pay ${pct >= 0 ? '$pct% more' : '${-pct}% less'} Trion');
  }
  if (def.misfireChance != null) {
    bits.add('have a ${(def.misfireChance! * 100).round()}% chance to hit the '
        'wrong target');
  }
  for (final entry in def.flatStatModifiers.entries) {
    final v = entry.value;
    bits.add(
      'have ${statLabel[entry.key] ?? entry.key.name} '
      '${v >= 0 ? '+' : ''}${_formatNumber(v)}',
    );
  }
  for (final stat in def.zeroedStats) {
    bits.add('have ${statLabel[stat] ?? stat.name} reduced to zero');
  }
  if (def.turnStartDamage != null) {
    bits.add(
      'take ${def.turnStartDamage!.average.round()} damage at the start of '
      'each of $whose turns',
    );
  }
  if (def.turnStartHeal != null) {
    bits.add(
      'heal ${def.turnStartHeal!.average.round()} at the start of each of '
      '$whose turns',
    );
  }
  if (def.disadvantageRollTags.isNotEmpty) bits.add('roll at a disadvantage');

  final subject = onSelf ? 'You' : 'They';
  final what = bits.isEmpty
      ? '$subject are affected by ${def.name}'
      : '$subject ${bits.join(', ')}';
  return '$what. '
      '${describeStatusDuration(def.defaultDurationTurns, onSelf: onSelf)}';
}

/// The tooltip for a status badge on a character in battle: what the effect
/// does, then how much of it is left.
///
/// [remainingTurns] is the live counter rather than the effect's default, and
/// it is spelled out in the same "whose turns" terms as everything else,
/// because a bare number does not say whether it survives to your next action.
String describeStatusBadge({
  required String id,
  required String name,
  int? remainingTurns,
  required bool onSelf,
  StatusEffectCatalog? statusCatalog,
}) {
  final catalog = statusCatalog ?? StatusEffectCatalog.defaultCatalog;
  final whose = onSelf ? 'your' : 'their';
  final String what;
  if (catalog.contains(id)) {
    what = describeStatusEffect(catalog[id], onSelf: onSelf)
        // The definition's own default duration is the wrong number here: the
        // live counter below is what is actually left.
        .split('. Active this turn')
        .first
        .split('. Lasts until')
        .first;
  } else {
    what = name;
  }
  final String left;
  if (remainingTurns == null) {
    left = 'Stays until it is removed.';
  } else if (remainingTurns <= 1) {
    left = 'Wears off when $whose next turn begins.';
  } else {
    left = 'Lasts $whose next ${remainingTurns - 1} '
        '${remainingTurns - 1 == 1 ? 'turn' : 'turns'}, '
        'then wears off at the start of the one after.';
  }
  return '$name. $what. $left';
}

/// One-paragraph player-facing description of what an active Trigger
/// does, computed from its data (mirrors the web demo's description).
String describeActiveTrigger(
  ActiveTrigger t, {
  StatusEffectCatalog? statusCatalog,
}) {
  final catalog = statusCatalog ?? StatusEffectCatalog.defaultCatalog;
  final parts = <String>[];
  final rangeWord = t.rangeTag.label;
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
  // Naming a status without saying what it does or how long it lasts leaves
  // the player nothing to plan with, so each one is spelled out. Whose turns
  // the duration counts depends on who ends up holding it.
  final onSelf = t.targetAffiliation != TargetAffiliation.opponent;
  for (final application in t.inflictedStatusEffects) {
    final def = catalog[application.statusEffectId];
    parts.add(
      '${onSelf ? 'Makes you' : 'Leaves the target'} '
      '${def.name}: ${describeStatusEffect(def, onSelf: onSelf)}',
    );
  }
  parts.add(
    'Costs ${t.trionCost} Trion. Usable again after ${t.cooldownTurns} '
    'turn${t.cooldownTurns == 1 ? '' : 's'} '
    '(${t.cooldownTurns * 2} if you use two or more abilities in one Full '
    'Arms Trigger turn).',
  );
  if (t.inflictedStatusEffects.isNotEmpty && onSelf) {
    // The timing question the interface never answered, written around the
    // ordinary turn rather than the FAT turn. Pairing a buff with an attack in
    // one turn takes two ability uses, so leading with that would be telling
    // the player the ability needs a Full Arms Trigger to do anything, which
    // is not how any ability should read.
    final lasts = t.inflictedStatusEffects
        .map((a) => catalog[a.statusEffectId].defaultDurationTurns ?? 99)
        .reduce((a, b) => a > b ? a : b);
    parts.add(
      lasts > 1
          ? 'It is still up on your next turn, so this turn sets up the attack '
              'you make then.'
          : 'It covers the opponent\'s reply and is gone before you act again.',
    );
  }
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

/// Player-facing descriptions of the stateful passive-counter behaviours
/// (these are logic, not flat stat mods, so [describePassiveEffect] alone
/// would report "No stat effect"). See design section 6.2.
const passiveCounterDescription = <PassiveCounterKind, String>{
  PassiveCounterKind.draegor:
      'Each ability you use builds a stack of Enmity; at 5 stacks it becomes '
      'Regret. While Regret is up, if an enemy chains 2+ abilities in a FAT '
      'turn, your '
      "squad's Team Efficiency Grade rises 2 tiers for 2 turns (or, if "
      'already SS+, your highest-Affinity ally’s Trion Affinity '
      'doubles). Max 3 per battle.',
  PassiveCounterKind.nullhymn:
      'Builds a stack of Discord when an enemy uses a Black Trigger against '
      'your team or inflicts a status on the holder. At 5 stacks it '
      'discharges (twice per '
      'battle): permanently drops the most-recently-active enemy Black '
      'Trigger one resonance grade - or, if no enemy runs one, purges your '
      "team's debuffs and reflects them onto whoever applied the most.",
  PassiveCounterKind.reckoning:
      'Builds a stack of Debt when an enemy crits your team or uses a 2+ '
      'cooldown ability against it. At 6 stacks it comes due: the worst '
      'offender’s '
      'cooldowns are extended, their next attack is forced to a critical '
      'miss, and your team levies their Trion.',
  PassiveCounterKind.gravehour:
      'At the end of each enemy turn, if they dealt no damage or left an '
      'enemy at 30% HP or below, the holder makes a free, uncounterable '
      'finisher on the lowest-HP enemy (who cannot be healed next turn). '
      '3-turn cooldown.',
  PassiveCounterKind.coldread:
      'At the start of your turn, secretly marks an enemy. If they take a '
      'damaging action you earn a reward that alternates each correct read '
      '(Levy first): Levy their costliest action’s Trion, then Seize '
      '(+2 to your whole squad’s rolls for 1 turn). A wrong read docks '
      'your next Trion gain.',
  PassiveCounterKind.ironvow:
      'Each turn a random attack type is sanctioned (never last turn’s). '
      'Attack with it for a Sanctioned Strike: unblockable, strips a buff, '
      'and brands the target (repeating an ability two turns running lands '
      'weakened). Cost: your other allies are left vulnerable to that type '
      'until your next turn. 3 per battle.',
};

String describeTrigger(Trigger t) => switch (t) {
  ActiveTrigger a => describeActiveTrigger(a),
  PassiveTrigger p => p.counterKind != null
      ? (passiveCounterDescription[p.counterKind!] ??
          describePassiveEffect(p.effect))
      : describePassiveEffect(p.effect),
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
