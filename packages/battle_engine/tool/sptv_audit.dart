// Dumps what item #3 (SPTV) has to price: every active ability's economics,
// every status effect's magnitude and duration, and every reactive duration.
//
//   dart run tool/sptv_audit.dart
//
// This is the descriptive half. It says what the catalog costs today, not
// what it should cost, so the pricing rule can be calibrated against live
// numbers instead of guessed at. Nothing here reads a proposed SP scale.
import 'package:battle_engine/battle_engine.dart';

String f(num v, [int places = 1]) => v.toStringAsFixed(places);

/// Expected output of one use, summed across every target and every hit.
/// Ignores the to-hit roll: this is the ceiling an ability is priced at.
double perUseOutput(ActiveTrigger t) {
  final dmg = (t.damage?.average ?? 0) * t.targetCount * t.hitsPerUse;
  final heal = (t.healAmount?.average ?? 0) * (t.healsCasterInstead ? 1 : t.targetCount);
  return dmg + heal;
}

/// What the ability is worth per turn of ownership: an ability on a 2-turn
/// cooldown is available one turn in three.
double throughput(ActiveTrigger t) => perUseOutput(t) / (t.cooldownTurns + 1);

void median(String label, List<double> xs) {
  if (xs.isEmpty) {
    print('  $label: none');
    return;
  }
  final s = List.of(xs)..sort();
  final mid = s.length.isOdd
      ? s[s.length ~/ 2]
      : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
  final mean = s.reduce((a, b) => a + b) / s.length;
  print('  $label: n=${s.length}  median ${f(mid)}  mean ${f(mean)}  '
      'min ${f(s.first)}  max ${f(s.last)}');
}


/// The opposed d20 both the to-hit roll and the infliction contest use:
/// causer d20+[gap] against target d20, ties to the causer, a natural 20 on
/// the causer's die always succeeds and a natural 1 always fails. Mirrors
/// CombatEngine.resolveAttackRoll and StatusEffectEngine.resolveInfliction.
double opposed(int gap) {
  var wins = 0;
  for (var a = 1; a <= 20; a++) {
    for (var d = 1; d <= 20; d++) {
      if (a == 20) {
        wins++;
      } else if (a == 1) {
        // always fails
      } else if (a + gap >= d) {
        wins++;
      }
    }
  }
  return wins / 400;
}

/// Advantage rolls two dice and keeps the higher, which is worth a flat
/// modifier of roughly this much. Solved by finding the modifier that gives
/// the same average success rate across the gaps the roster actually spans.
double advantageModifierEquivalent() {
  double advantageRate(int gap) {
    var wins = 0;
    for (var a1 = 1; a1 <= 20; a1++) {
      for (var a2 = 1; a2 <= 20; a2++) {
        final a = a1 > a2 ? a1 : a2;
        for (var d = 1; d <= 20; d++) {
          if (a == 20) {
            wins++;
          } else if (a == 1) {
            // always fails
          } else if (a + gap >= d) {
            wins++;
          }
        }
      }
    }
    return wins / (400 * 20);
  }

  var best = 0.0;
  var bestErr = double.infinity;
  for (var m = 0.0; m <= 8.0; m += 0.05) {
    var err = 0.0;
    for (var gap = -4; gap <= 6; gap++) {
      // Interpolate the flat-modifier curve at a fractional modifier.
      final lo = opposed(gap + m.floor());
      final hi = opposed(gap + m.floor() + 1);
      final flat = lo + (hi - lo) * (m - m.floorToDouble());
      final diff = advantageRate(gap) - flat;
      err += diff * diff;
    }
    if (err < bestErr) {
      bestErr = err;
      best = m;
    }
  }
  return best;
}

void main() {
  final triggers = TriggerCatalog.defaultCatalog;
  final blacks = BlackTriggerCatalog.defaultCatalog;
  final statuses = StatusEffectCatalog.defaultCatalog;

  final actives = triggers.activeTriggers.toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  final blackActives = [
    for (final bt in blacks.all) ...bt.activeAbilities,
  ]..sort((a, b) => a.id.compareTo(b.id));

  print('=' * 78);
  print('A. ACTIVE ABILITY ECONOMICS (${actives.length} catalog + '
      '${blackActives.length} Black Trigger)');
  print('=' * 78);
  print('perUse = average damage x targets x hits, plus heal. Ignores the '
      'to-hit roll.');
  print('thru   = perUse / (cooldown + 1), the per-turn value of owning it.');
  print('perTri = perUse / Trion cost.');
  print('');
  print('id'.padRight(26) +
      'band'.padRight(7) +
      'type'.padRight(9) +
      'sub'.padRight(8) +
      'tri'.padLeft(4) +
      'cd'.padLeft(4) +
      'eq'.padLeft(4) +
      'perUse'.padLeft(8) +
      'thru'.padLeft(7) +
      'perTri'.padLeft(8) +
      '  statuses');
  for (final t in actives) {
    final st = t.inflictedStatusEffects.map((s) => s.statusEffectId).join(',');
    final extra = [
      if (t.uniqueBehavior != null) 'unique:${t.uniqueBehavior!.name}',
      if (t.armsReactive != null)
        'arms:${t.armsReactive!.name}(${t.armsReactiveDefaultTurns ?? "until fired"})',
      if (t.targetAffiliation != TargetAffiliation.opponent)
        'on:${t.targetAffiliation.name}',
    ].join(' ');
    print(t.id.padRight(26) +
        t.rangeTag.name.padRight(7) +
        t.abilityType.name.padRight(9) +
        t.abilitySubtype.name.padRight(8) +
        '${t.trionCost}'.padLeft(4) +
        '${t.cooldownTurns}'.padLeft(4) +
        '${t.equipCost}'.padLeft(4) +
        f(perUseOutput(t)).padLeft(8) +
        f(throughput(t)).padLeft(7) +
        f(t.trionCost == 0 ? 0 : perUseOutput(t) / t.trionCost, 2).padLeft(8) +
        '  ${[st, extra].where((s) => s.isNotEmpty).join(' | ')}');
  }

  print('');
  print('-- distribution of perUse, damaging opponent-targeted abilities --');
  final damaging = actives
      .where((t) =>
          t.targetAffiliation == TargetAffiliation.opponent && t.damage != null)
      .toList();
  median('all damaging', [for (final t in damaging) perUseOutput(t)]);
  for (final band in RangeTag.values) {
    median('band ${band.name}',
        [for (final t in damaging.where((t) => t.rangeTag == band)) perUseOutput(t)]);
  }
  for (final at in AbilityType.values) {
    median('type ${at.name}',
        [for (final t in damaging.where((t) => t.abilityType == at)) perUseOutput(t)]);
  }
  for (final sub in AbilitySubtype.values) {
    median('sub ${sub.name}',
        [for (final t in damaging.where((t) => t.abilitySubtype == sub)) perUseOutput(t)]);
  }
  print('');
  print('-- distribution of throughput and cost --');
  median('throughput', [for (final t in damaging) throughput(t)]);
  median('perTrion', [
    for (final t in damaging.where((t) => t.trionCost > 0))
      perUseOutput(t) / t.trionCost
  ]);
  median('trionCost', [for (final t in actives) t.trionCost.toDouble()]);
  median('cooldown', [for (final t in actives) t.cooldownTurns.toDouble()]);
  median('equipCost', [for (final t in actives) t.equipCost.toDouble()]);

  print('');
  print('=' * 78);
  print('B. WHAT AN ACTION BUYS WHEN IT IS NOT DAMAGE');
  print('=' * 78);
  print('Every active that deals no damage to an opponent. Item #5\'s '
      'acceptance test');
  print('applies to each of these: it must pay for its own action within its '
      'own duration.');
  print('');
  for (final t in actives) {
    final dealsDamage =
        t.damage != null && t.targetAffiliation == TargetAffiliation.opponent;
    if (dealsDamage) continue;
    final bits = <String>[
      if (t.healAmount != null)
        'heal ${f(t.healAmount!.average)} x${t.targetCount}',
      for (final s in t.inflictedStatusEffects)
        '${s.statusEffectId}'
            '${s.durationTurnsOverride != null ? "(${s.durationTurnsOverride}t)" : ""}',
      if (t.armsReactive != null) 'arms ${t.armsReactive!.name}',
      if (t.uniqueBehavior != null) 'unique ${t.uniqueBehavior!.name}',
    ];
    print('${t.id.padRight(26)}${"${t.trionCost}tri".padLeft(6)} '
        '${"cd${t.cooldownTurns}".padLeft(4)} '
        '${t.targetAffiliation.name.padRight(9)}${bits.join(', ')}');
  }

  print('');
  print('=' * 78);
  print('C. STATUS REACHABILITY');
  print('=' * 78);
  final appliedBy = <String, List<String>>{};
  for (final t in actives) {
    for (final s in t.inflictedStatusEffects) {
      appliedBy.putIfAbsent(s.statusEffectId, () => []).add(t.id);
    }
  }
  for (final t in blackActives) {
    for (final s in t.inflictedStatusEffects) {
      appliedBy.putIfAbsent(s.statusEffectId, () => []).add('BT:${t.id}');
    }
  }
  final ids = statuses.all.map((d) => d.id).toList()..sort();
  print('${ids.length} status effects. Catalog-reachable means some Trigger '
      'lists it in');
  print('inflictedStatusEffects. Everything else is applied by engine code '
      'or by nothing.');
  print('');
  final unreachable = <String>[];
  for (final id in ids) {
    final by = appliedBy[id];
    if (by == null) {
      unreachable.add(id);
    } else {
      print('  ${id.padRight(22)} ${by.join(', ')}');
    }
  }
  print('');
  print('NOT applied by any Trigger (${unreachable.length}): '
      '${unreachable.join(', ')}');

  print('');
  print('=' * 78);
  print('D. STATUS MAGNITUDES AND DURATIONS');
  print('=' * 78);
  print('Every field SPTV has to put a number on. "-" is a field the effect '
      'does not use.');
  print('');
  for (final id in ids) {
    final d = statuses[id];
    final bits = <String>[];
    if (d.preventsActions) bits.add('PREVENTS ACTIONS');
    if (d.preventsReposition) bits.add('pins in place');
    if (d.preventsTargeting) bits.add('untargetable');
    if (d.preventsHealing) bits.add('no healing');
    if (d.preventsAllyInteraction) bits.add('no ally interaction');
    if (d.forcesNextAttackMiss) bits.add('next attack misses');
    if (d.forcesRepetitionOfLastAbility) bits.add('must repeat last ability');
    if (d.locksRandomAbilityEachTurn) bits.add('locks 1 random ability/turn');
    if (d.locksOriginFromData) bits.add('locks one origin');
    if (d.cannotTargetSource) bits.add('cannot target source');
    if (d.sourceHasAdvantageAgainstTarget) bits.add('source has advantage');
    if (d.rangedTargetsReducedByOne) bits.add('ranged targets -1');
    for (final e in d.zeroedStats) {
      bits.add('${e.name}=0');
    }
    d.flatStatModifiers.forEach((k, v) =>
        bits.add('${k.name} ${v > 0 ? "+" : ""}${f(v, 0)}'));
    d.perRemainingTurnStatModifiers.forEach((k, v) =>
        bits.add('${k.name} ${v > 0 ? "+" : ""}${f(v, 0)}/turn remaining'));
    for (final r in d.damageTypeInteractions) {
      bits.add(r.kind == DamageInteractionKind.immune
          ? 'immune ${r.damageType.name}'
          : 'vulnerable ${r.damageType.name} x${f(r.vulnerableMultiplier)}');
    }
    if (d.turnStartDamage != null) {
      bits.add('tick ${f(d.turnStartDamage!.average)} '
          '${d.turnStartDamageType?.name ?? "?"}/turn');
    }
    if (d.turnStartHeal != null) {
      bits.add('heal ${f(d.turnStartHeal!.average)}/turn');
    }
    if (d.trionCapacityDrainPercentToCauser != null) {
      bits.add('drains ${f(d.trionCapacityDrainPercentToCauser! * 100, 0)}% '
          'Trion Capacity/turn');
    }
    if (d.vulnerableToRandomDamageTypesCount != null) {
      bits.add('vulnerable to ${d.vulnerableToRandomDamageTypesCount} '
          'random damage types');
    }
    if (d.allDamageTakenMultiplier != null) {
      bits.add('damage taken x${f(d.allDamageTakenMultiplier!, 2)}');
    }
    if (d.outgoingDamageMultiplier != null) {
      bits.add('damage dealt x${f(d.outgoingDamageMultiplier!, 2)}');
    }
    if (d.trionCostMultiplier != null) {
      bits.add('Trion cost x${f(d.trionCostMultiplier!, 2)}');
    }
    if (d.repeatAbilityDamageMultiplier != null) {
      bits.add('repeat damage x${f(d.repeatAbilityDamageMultiplier!, 2)}');
    }
    if (d.misfireChance != null) {
      bits.add('${f(d.misfireChance! * 100, 0)}% misfire onto an ally');
    }
    for (final tag in d.advantageRollTags) {
      bits.add('advantage: ${tag.name}');
    }
    for (final tag in d.disadvantageRollTags) {
      bits.add('disadvantage: ${tag.name}');
    }
    final dur = d.defaultDurationTurns == null
        ? 'until removed'
        : '${d.defaultDurationTurns}t';
    print('  ${d.id.padRight(22)}${dur.padRight(14)}'
        '${bits.isEmpty ? "NO MECHANICAL EFFECT" : bits.join('; ')}');
  }

  print('');
  print('=' * 78);
  print('E. REACTIVE DURATIONS (armsReactiveDefaultTurns, all first-pass)');
  print('=' * 78);
  for (final t in [...actives, ...blackActives]) {
    if (t.armsReactive == null) continue;
    print('  ${t.id.padRight(26)}${t.armsReactive!.name.padRight(22)}'
        '${t.armsReactiveDefaultTurns ?? "until fired"}');
  }

  print('');
  print('=' * 78);
  print('F. THE ECONOMY THESE PRICES SIT IN');
  print('=' * 78);
  const tier = TrionTierConfig.defaults;
  print('  Trion income per team per turn: '
      'Low ${tier.lowAmount}, Medium ${tier.mediumAmount}, '
      'High ${tier.highAmount}');
  print('  Base chances: Low->Med ${f(tier.baseChanceLowToMedium * 100, 0)}%, '
      'Med->High ${f(tier.baseChanceMediumToHigh * 100, 0)}%, '
      '+${f(tier.affinityWeightPerPoint * 100, 0)}pp per point of squad '
      'Trion Affinity');
  final roster = CharacterRoster.defaultRoster.all.toList();
  median('roster maxHealth',
      [for (final c in roster) c.baseStats.maxHealth.toDouble()]);
  median('roster armor', [for (final c in roster) c.baseStats.armor.toDouble()]);
  median('roster attack',
      [for (final c in roster) c.baseStats.attack.toDouble()]);
  median('roster defense',
      [for (final c in roster) c.baseStats.defense.toDouble()]);
  median('roster trionCapacity',
      [for (final c in roster) c.baseStats.trionCapacity.toDouble()]);
  median('roster statusEffectInfliction',
      [for (final c in roster) c.baseStats.statusEffectInfliction.toDouble()]);
  median('roster statusEffectResistance',
      [for (final c in roster) c.baseStats.statusEffectResistance.toDouble()]);
  print('  Loadout: exactly '
      '${LoadoutRulesConfig.defaults.requiredActiveAbilityCount} active '
      'abilities, at most '
      '${LoadoutRulesConfig.defaults.maxEquippedTriggers} equipped items, '
      'paid for out of Trion Capacity.');


  print('');
  print('=' * 78);
  print('H. WHAT A POINT IS WORTH');
  print('=' * 78);
  print('Both the to-hit roll and the status-infliction contest are the same '
      'opposed');
  print('d20: higher total wins, ties to the causer, natural 20 always '
      'succeeds and');
  print('natural 1 always fails. So one point of Attack, Defense, Infliction '
      'or');
  print('Resistance buys the same thing, and this is how much of it.');
  print('');
  for (var gap = -6; gap <= 8; gap += 1) {
    final p = opposed(gap);
    final marginal = opposed(gap + 1) - p;
    print('  gap ${gap.toString().padLeft(3)}   '
        'succeeds ${f(p * 100)}%   '
        '+1 more point buys ${f(marginal * 100)} points of that');
  }
  print('');
  print('  advantage on the roll is worth about '
      '${f(advantageModifierEquivalent())} points of modifier');
  print('');

  final roster2 = CharacterRoster.defaultRoster.all.toList();
  final hitRates = <double>[];
  final inflictRates = <double>[];
  final riderRates = <double>[];
  for (final a in roster2) {
    for (final d in roster2) {
      final hit = opposed(a.baseStats.attack - d.baseStats.defense);
      final inflict = opposed(a.baseStats.statusEffectInfliction -
          d.baseStats.statusEffectResistance);
      hitRates.add(hit);
      inflictRates.add(inflict);
      riderRates.add(hit * inflict);
    }
  }
  print('  Across all ${roster2.length}x${roster2.length} roster matchups, '
      'before any status modifies a roll:');
  median('attack lands', [for (final x in hitRates) x * 100]);
  median('infliction contest won', [for (final x in inflictRates) x * 100]);
  median('hostile rider lands (both)', [for (final x in riderRates) x * 100]);
  print('');
  print('  A hostile rider needs the attack to land first: the infliction '
      'contest is');
  print('  attempted inside resolveHitAgainst, after the miss branch has '
      'returned.');
  print('  An ally-targeted or self-targeted status skips both rolls and '
      'always lands.');

  print('');
  print('=' * 78);
  print('G. REACHABILITY CLOSURE');
  print('=' * 78);
  print('Section C only asked which Triggers list a status. Engine code '
      'applies more of');
  print('them, and Unmaking applies a debuff only when the matching buff is '
      'already');
  print('there, so reachability is a closure rather than a lookup. The two '
      'lists below');
  print('are read off turn_engine.dart by hand; re-derive them with');
  print('  grep -n -A4 "statusEffectEngine.apply(" '
      'lib/src/engine/turn_engine.dart');
  print('');

  // Literal ids passed to StatusEffectEngine.apply from engine code, as of
  // the #2 merge. Nullhymn's discharge re-applies a debuff the holder is
  // already carrying, so it creates no new reachability and is not listed.
  const engineApplied = <String>{
    'stunned',
    'silenced',
    'exposed',
    'cursed',
    'interdict',
    'forced_critical_miss',
    'called_shot_stat_zero',
    'minds_eye_reveal',
    'forced_choice',
    'isolation',
    'untargetable',
    'echoing_doubt',
    'karmic_bind',
    'vow_of_the_duel',
  };

  // TurnEngine._buffToDebuffInversion: Unmaking turns a buff the target
  // already has into its debuff twin. The debuff is only reachable if the
  // buff is.
  const inversion = <String, String>{
    'empowered': 'weakened',
    'guarded': 'exposed',
    'inspired': 'fatigued',
    'hastened': 'chilled',
    'prepared': 'reeling',
    'braced': 'slowed',
    'overcharged': 'choked',
    'warded': 'hexed',
    'focused': 'poisoned',
    'regenerating': 'bleeding',
  };

  final direct = <String>{...appliedBy.keys, ...engineApplied};
  final reachable = Set<String>.from(direct);
  var grew = true;
  while (grew) {
    grew = false;
    inversion.forEach((buff, debuff) {
      if (reachable.contains(buff) && reachable.add(debuff)) grew = true;
    });
  }

  final viaInversionOnly = reachable.difference(direct);
  final orphans = ids.where((id) => !reachable.contains(id)).toList();

  print('  applied by a Trigger        ${appliedBy.length}');
  print('  applied by engine code      ${engineApplied.length} '
      '(${engineApplied.difference(appliedBy.keys.toSet()).length} of them '
      'not also on a Trigger)');
  print('  reachable only by Unmaking  ${viaInversionOnly.length}'
      '${viaInversionOnly.isEmpty ? "" : ": ${viaInversionOnly.join(", ")}"}');
  print('  reachable in total          ${reachable.length} of ${ids.length}');
  print('');
  print('  NOTHING APPLIES THESE (${orphans.length}):');
  for (final id in orphans) {
    print('    ${id.padRight(22)}${statuses[id].defaultDurationTurns ?? "-"}t');
  }
  print('');
  print('  Dead inversion pairs (the debuff has no other route in, and its '
      'buff has');
  print('  no route in either, so Unmaking can never produce it):');
  inversion.forEach((buff, debuff) {
    if (!reachable.contains(buff) && !direct.contains(debuff)) {
      print('    $buff -> $debuff');
    }
  });

}
