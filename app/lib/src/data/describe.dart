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
/// Since item #D this is one sentence rather than three. The engine counts an
/// effect down at the **end of its holder's turn** and never counts the turn
/// it was applied on, so a duration of N means the holder's next N turns,
/// whoever applied it and whenever. A 1-turn Stun costs its victim exactly one
/// action; a 2-turn buff covers two of your own turns. The effect is also live
/// for the rest of the turn it landed on, which is a free remainder rather
/// than one of the N.
///
/// [onSelf] switches the possessive, since the turns being counted are the
/// holder's, and the holder is the target for a debuff.
String describeStatusDuration(int? turns, {required bool onSelf}) {
  if (turns == null) return 'Lasts until it is removed.';
  final whose = onSelf ? 'your' : 'their';
  if (turns <= 1) {
    return 'Lasts through $whose next turn.';
  }
  return 'Lasts through $whose next $turns turns.';
}

/// The two effects whose value is not mechanical, so no field could carry it.
///
/// Item 13b's rule is that a description is computed from the definition, so a
/// re-priced magnitude updates its own text. These two are the exception the
/// SPTV review named (decision #B): what they are worth is information, and a
/// field that said "reveals something" would be a placeholder wearing a
/// field's clothes.
/// A damage type in the words a player reads: the enum's own name, capital
/// first, because those names are already the words.
String _damageTypeLabel(DamageType type) =>
    type.name[0].toUpperCase() + type.name.substring(1);

const Map<String, String> _writtenStatusDescriptions = {
  'minds_eye_reveal':
      'have every ability, cooldown and Trion reserve laid bare to whoever '
      'applied this, who can then plan around what they see',
  'called_shot_stat_zero':
      'have one named stat reduced to zero, chosen by whoever fired the shot '
      'when it landed',
};

/// What a status effect actually does, in plain terms, followed by how long
/// it lasts. This is the line the battle interface shows for a status badge,
/// and the line an ability's description borrows when it inflicts one.
///
/// Deliberately short: the full prose pass over all 62 effects is its own
/// item. This states the mechanical effect and the duration, which are the two
/// things a player cannot work out by looking.
/// The rolls a status effect touches, in the words a player uses for them.
///
/// Ordered by the enum rather than by the set's iteration order, so an effect
/// that names two of them always reads the same way round.
String _rollTagList(Set<StatusRollTag> tags) {
  const label = {
    StatusRollTag.attackRoll: 'attack rolls',
    StatusRollTag.rangedAttackRoll: 'ranged attack rolls',
    StatusRollTag.statusResistanceRoll: 'status-resistance rolls',
  };
  // An effect touching both attack rolls and ranged ones touches every attack
  // roll there is, and saying both is worse than saying that.
  final named = {...tags};
  if (named.contains(StatusRollTag.attackRoll)) {
    named.remove(StatusRollTag.rangedAttackRoll);
  }
  final parts = [
    for (final tag in StatusRollTag.values)
      if (named.contains(tag)) label[tag]!,
  ];
  if (parts.length == 1) return parts.single;
  return '${parts.take(parts.length - 1).join(', ')} and ${parts.last}';
}

String describeStatusEffect(
  StatusEffectDefinition def, {
  required bool onSelf,
  bool includeDuration = true,
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
    // Exactly what it rolls, and of what type. "3 damage" for Electrocuted's
    // 1d4 says a number the dice do not promise, and the type is what decides
    // whether a resistance or a vulnerability changes it.
    final type = def.turnStartDamageType;
    bits.add(
      'take ${def.turnStartDamage!.label}'
      '${type == null ? '' : ' ${_damageTypeLabel(type)}'} damage at the '
      'start of each of $whose turns',
    );
  }
  if (def.turnStartHeal != null) {
    bits.add(
      'heal ${def.turnStartHeal!.label} at the start of each of $whose turns',
    );
  }
  // Which rolls, not just "rolls". Poisoned and Threatened both used to read
  // "You roll at a disadvantage", which is the same sentence for two effects
  // that hurt in completely different ways: one blunts every attack you make,
  // the other only the ones you make at range.
  if (def.disadvantageRollTags.isNotEmpty) {
    bits.add('roll ${_rollTagList(def.disadvantageRollTags)} at a '
        'disadvantage');
  }
  if (def.advantageRollTags.isNotEmpty) {
    bits.add('roll ${_rollTagList(def.advantageRollTags)} at an advantage');
  }

  // Item 13b. Everything below this line was a field the engine read and the
  // description did not, which is how sixteen effects came to introduce
  // themselves by name and say nothing else.
  for (final entry in def.perRemainingTurnStatModifiers.entries) {
    final v = entry.value;
    bits.add(
      'have ${statLabel[entry.key] ?? entry.key.name} '
      '${v >= 0 ? '+' : '-'}${_formatNumber(v.abs())} for every turn still '
      'left on this, so it fades as it runs out',
    );
  }
  for (final rule in def.damageTypeInteractions) {
    final type = _damageTypeLabel(rule.damageType);
    if (rule.kind == DamageInteractionKind.immune) {
      bits.add('take no $type damage at all');
    } else {
      final times = _formatNumber(rule.vulnerableMultiplier);
      bits.add('take ${times}x damage from $type');
    }
  }
  if (def.vulnerableToRandomDamageTypesCount != null) {
    final n = def.vulnerableToRandomDamageTypesCount!;
    bits.add('take double damage from $n damage '
        '${n == 1 ? 'type' : 'types'} picked at random when this lands');
  }
  if (def.trionCapacityDrainPercentToCauser != null) {
    final pct = (def.trionCapacityDrainPercentToCauser! * 100).round();
    bits.add('lose $pct% of $whose Trion Capacity to whoever applied this at '
        'the start of each of $whose turns');
  }
  if (def.locksOriginFromData) {
    bits.add('cannot use abilities of one named origin');
  }
  if (def.locksAbilityTypeFromData) {
    bits.add('cannot use one whole ability type, melee, ranged or psychic');
  }
  if (def.locksToSingleChosenAbility) {
    bits.add('may use only one named ability and nothing else');
  }
  if (def.repeatAbilityDamageMultiplier != null) {
    final pct =
        ((1 - def.repeatAbilityDamageMultiplier!) * 100).round();
    bits.add('deal $pct% less damage when repeating the ability used last '
        'turn');
  }
  if (def.forcesNextAttackCriticalMiss) {
    bits.add('miss the next attack critically');
  }
  if (def.sharesMagnitudeWithBoundEnemy) {
    bits.add('pass part of every wound and every heal on to the enemy bound '
        'to $whose fate');
  }
  if (def.randomizesOwnTargeting) bits.add('pick $whose targets at random');

  final subject = onSelf ? 'You' : 'They';
  final written = _writtenStatusDescriptions[def.id];
  final what = written != null
      ? '$subject $written'
      : bits.isEmpty
          ? '$subject are affected by ${def.name}'
          : '$subject ${bits.join(', ')}';
  if (!includeDuration) return '$what.';
  return '$what. '
      '${describeStatusDuration(def.defaultDurationTurns, onSelf: onSelf)}';
}

/// The tooltip for a status badge on a character in battle: what the effect
/// does, then how much of it is left.
///
/// [remainingTurns] is the live counter rather than the effect's default, and
/// it is spelled out in the same "whose turns" terms as everything else,
/// because a bare number does not say whether it survives to your next action.
/// Since item #D the counter is honest: it is the number of the holder's turns
/// still to come, and the last of them is a whole turn rather than a moment.
String describeStatusBadge({
  required String id,
  required String name,
  int? remainingTurns,
  required bool onSelf,
  int stacks = 1,
  StatusEffectCatalog? statusCatalog,
}) {
  final catalog = statusCatalog ?? StatusEffectCatalog.defaultCatalog;
  final whose = onSelf ? 'your' : 'their';
  final String what;
  if (catalog.contains(id)) {
    // The definition's own default duration is the wrong number here: the
    // live counter below is what is actually left. This used to be done by
    // splitting the sentence back off the string, which quietly stopped
    // matching the moment item #D reworded it, printing both numbers.
    what = describeStatusEffect(
      catalog[id],
      onSelf: onSelf,
      includeDuration: false,
    );
  } else {
    what = '$name.';
  }
  final String left;
  if (remainingTurns == null) {
    left = 'Stays until it is removed.';
  } else if (remainingTurns <= 1) {
    left = 'One turn left: it wears off at the end of $whose next turn.';
  } else {
    left = '$remainingTurns turns left, counting $whose next one.';
  }
  if (stacks > 1) {
    // Item 5b: a stack multiplies every magnitude the effect carries, so the
    // count is the difference between a scratch and a problem.
    return '$name x$stacks. $what Everything it does is multiplied by '
        '$stacks. $left';
  }
  return '$name. $what $left';
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
  // Found in a playtest: every area ability described itself as an "attack
  // that hits all 3 targets at once", whoever it was aimed at and whether or
  // not it dealt damage. Guardian's Aegis is not an attack, and no area
  // ability hits three characters spread across three lines: it catches one
  // line. The opening clause says what the ability actually is, on three
  // axes: who it is aimed at, whether it is an attack, and what it reaches.
  // Two different questions, and conflating them called Mind's Eye a "Long
  // Range attack" when it deals no damage and only reads a Loadout.
  // Whose side the target is on decides which line an area covers; whether
  // there is damage on it decides whether the word "attack" is honest.
  final atEnemy = t.targetAffiliation == TargetAffiliation.opponent;
  final isAttack = atEnemy && t.damageType != null;
  final noun = isAttack ? 'attack' : 'ability';
  final whichLine = atEnemy ? 'one enemy line' : 'one of your own lines';
  // What the ability does to the people on that line. An attack hits them;
  // a ward does not "catch" anybody, it affects them.
  final reaches = atEnemy ? 'hitting' : 'affecting';
  String people(int n) => n == 1 ? '1 who stands' : '$n who stand';

  if (t.targetAffiliation == TargetAffiliation.self) {
    parts.add('Used on yourself. Nobody else is affected.');
  } else if (t.abilitySubtype == AbilitySubtype.aoe) {
    parts.add(
      '$rangeWord $noun. Covers $whichLine, $reaches up to '
      '${people(t.targetCount)} on it and nobody on another line.',
    );
  } else if (t.abilitySubtype == AbilitySubtype.burst) {
    parts.add(
      '$rangeWord $noun. ${t.hitsPerUse} hits, split across up to '
      '${t.targetCount} ${t.targetCount == 1 ? 'target' : 'targets'}.',
    );
  } else if (t.targetCount > 1) {
    // A unique ability aimed at more than one target used to describe itself
    // as single-target, which is simply not what Martyr's End does.
    parts.add('$rangeWord $noun on up to ${t.targetCount} targets.');
  } else if (t.targetAffiliation == TargetAffiliation.ally) {
    parts.add('$rangeWord ability, aimed at one ally.');
  } else {
    parts.add('$rangeWord $noun on a single target.');
  }
  if (t.damageType != null && t.damage != null) {
    parts.add(
      '${capitalize(t.damageType!.name)} damage, avg ${t.damage!.average.round()}'
      '${t.abilitySubtype == AbilitySubtype.burst ? ' per hit' : ''}.',
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
  // Who the status lands on, in words that survive an ability covering a
  // whole line: "makes you" is wrong when it is your front line rather than
  // you, and "leaves the target" is wrong when there are three of them.
  final recipient = switch (t.targetAffiliation) {
    TargetAffiliation.self => 'Makes you',
    TargetAffiliation.ally =>
      t.abilitySubtype == AbilitySubtype.aoe ? 'Everyone it covers becomes' : 'Makes the ally',
    TargetAffiliation.opponent =>
      t.abilitySubtype == AbilitySubtype.aoe ? 'Leaves everyone it hits' : 'Leaves the target',
  };
  for (final application in t.inflictedStatusEffects) {
    final def = catalog[application.statusEffectId];
    parts.add(
      '$recipient ${def.name}: '
      '${describeStatusEffect(def, onSelf: onSelf)}',
    );
  }
  if (t.uniqueBehavior != null) {
    final line = uniqueBehaviorDescription[t.uniqueBehavior!];
    if (line != null) parts.add(line);
  }
  if (t.armsReactive != null) {
    final line = reactiveDescription[t.armsReactive!];
    if (line != null) {
      parts.add(
        t.armsReactiveDefaultTurns == null
            ? '$line It stays armed until it fires.'
            : '$line It stays armed for ${t.armsReactiveDefaultTurns} '
                'turn${t.armsReactiveDefaultTurns == 1 ? '' : 's'}.',
      );
    }
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
      'Each turn a random ability type is sanctioned (never last turn’s). '
      'Attack with it for a Sanctioned Strike: unblockable, strips a buff, '
      'and brands the target (repeating an ability two turns running lands '
      'weakened). Cost: your other allies are left vulnerable to that type '
      'until your next turn. 3 per battle.',
};

/// What each counter actually does when it fires, in the player's own terms.
///
/// The arming half of a ward was invisible before this: an ability whose whole
/// point is the reactive it sets up described itself as "Affects the user
/// only", which tells nobody anything. A counter is a promise about the
/// opponent's next turn, so the description has to say what the promise is.
/// What each unique ability actually does, in the player's words.
///
/// Seventeen abilities carried a `uniqueBehavior` and no description of it,
/// so Martyr's End introduced itself as "Long Range attack on up to 3
/// targets. Costs 10 Trion." and stopped: no damage, no status, and not a
/// word about the thing that makes it Martyr's End. The mechanic was in the
/// engine, in the enum's own doc comments, and nowhere a player could reach.
///
/// Written off what the engine **does today**, not off what the enum's
/// comments describe. Several of these were specified with a choice the
/// caster makes, and the interface offers none of them yet: nothing passes
/// `uniqueData`, so Called Shot always zeroes Attack, Forced Choice always
/// locks the cheapest ability, Sensory Swap always moves the first effect it
/// finds, and Sunder Arms picks the caster's own loss at random. Promising a
/// choice the player cannot make would be the same defect in a new place.
const uniqueBehaviorDescription = <UniqueBehavior, String>{
  UniqueBehavior.sharedAgony:
      'Picks an enemy you have hit in melee this battle, at random. Rolls its '
      'damage, deals it to you in full, and deals 20% more than that to them. '
      'It can kill you.',
  UniqueBehavior.graveBargain:
      'Spends a chunk of your current health and deals exactly that much as '
      'true damage: no attack roll, and neither Armor nor Defense reduces it.',
  UniqueBehavior.martyrsEnd:
      'Only usable below a quarter health. You are removed from the battle, '
      'and every enemy takes heavy damage as you go.',
  UniqueBehavior.vowOfTheDuel:
      'Binds you to one enemy for 3 turns. You deal double damage to them, '
      'and in exchange you cannot act on anyone else and cannot be healed. If '
      'they are still standing when it ends, you are Stunned for 2 turns.',
  UniqueBehavior.sunderArms:
      'A strike that permanently destroys one of the target\'s equipped '
      'Triggers for the rest of the battle, picked at random. It costs you '
      'one of your own the same way.',
  UniqueBehavior.curvingShot:
      'Ignores the first ward, dodge or counter the target has up and lands '
      'anyway.',
  UniqueBehavior.calledShot:
      'No damage. Takes the target\'s Attack to zero for the effect\'s '
      'duration.',
  UniqueBehavior.mindsEye:
      'Reveals one enemy\'s whole Loadout in their panel, so you can read '
      'what they are carrying before deciding. You cannot use it on yourself.',
  UniqueBehavior.forcedChoice:
      'Next turn the target may use only their cheapest ability, whatever '
      'else they were holding.',
  UniqueBehavior.memoryTheft:
      'Copies the last ability the target used. You may cast it once next '
      'turn, out of this ability\'s own slot.',
  UniqueBehavior.sensorySwap:
      'Moves one active status effect off the first target and onto the '
      'second, keeping the turns it had left.',
  UniqueBehavior.dreadResonance:
      'Damage scales with how much damage that enemy has dealt this battle, '
      'so it punishes whoever has been hurting you most.',
  UniqueBehavior.isolation:
      'For 2 turns that enemy cannot be healed or buffed by their allies, and '
      'cannot heal or buff them either.',
  UniqueBehavior.illusoryDouble:
      'They cannot be targeted at all during the opponent\'s next turn. It '
      'starts with one charge and gains another every time one of your squad '
      'is defeated.',
  UniqueBehavior.echoingDoubt:
      'The target\'s next attack misses outright while they still pay its '
      'Trion and its cooldown, and they are Silenced afterwards. No roll: it '
      'simply happens.',
  UniqueBehavior.karmicBind:
      'For 3 turns, part of every wound and every heal on you is dealt to a '
      'chosen enemy as unavoidable damage. How large a part scales with your '
      'Team Spirit.',
  UniqueBehavior.unmaking:
      'Turns every buff the target is holding into its opposite for whatever '
      'duration was left: Empowered becomes Weakened, Guarded becomes '
      'Exposed, and so on down the list.',
};

const reactiveDescription = <ReactiveKind, String>{
  ReactiveKind.reflectNonAoe:
      'Counter: the next single-target hit against you is reflected straight '
      'back at whoever threw it, at full effect. An area attack ignores it and '
      'leaves it standing.',
  ReactiveKind.dodgeMeleeSingle:
      'Counter: dodge the next single-target melee attack against you and '
      'answer it with a free counter-hit. Once per battle.',
  ReactiveKind.negateByOrigin:
      'Counter: name a kind of power. The next attack of that kind against the '
      'warded ally is cancelled outright, and its attacker is Stunned for 2 '
      'turns.',
  ReactiveKind.burstMitigation:
      'Counter: a multi-hit burst against you only lands its first hit. Every '
      'later hit in the same burst is suppressed.',
  ReactiveKind.cooldownSabotage:
      'Counter: when a ranged attack hits you, that ability goes on double '
      'cooldown for its owner.',
  ReactiveKind.redirectToOwnAlly:
      'Counter: the next single-target attack on the protected ally is '
      'redirected onto one of the attacker\'s own squad at random. You are '
      'Exposed while it is armed.',
  ReactiveKind.trapOnAction:
      'Trap, laid on an enemy: the next time they use a damaging ability it is '
      'countered outright and they take the trap damage instead.',
  ReactiveKind.nullifyAoe:
      'Mark, laid on an enemy: the next area attack they aim at your squad is '
      'nullified, and you borrow the ability for 2 turns.',
  ReactiveKind.bankDamage:
      'Counter: while you are Guarded or Braced, damage you take is banked '
      'instead of lost. Your next attack deals all of it as bonus damage.',
  ReactiveKind.enrichSurviveLethal:
      'Counter: when your survive-lethal charge saves you, every status you '
      'are carrying lasts twice as long and whoever struck you is Stunned for '
      '2 turns.',
  ReactiveKind.refuseToBail:
      'Pre-declared: the next time you would be reduced to 0 health, you are '
      'not. You stay standing on 1 health and act one more time, and are then '
      'gone for good. No body is left to recall, so your squad gets no Trion '
      'Salvage.',
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
