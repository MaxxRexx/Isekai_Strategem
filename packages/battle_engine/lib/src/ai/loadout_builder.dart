import '../constants.dart';
import '../models/black_trigger.dart';
import '../models/character.dart';
import '../models/loadout.dart';
import '../models/resonance.dart';
import '../models/trigger.dart';
import 'ai_profile.dart';

/// Builds a valid [Loadout] for [character] matching [profile]'s
/// strategic identity: Black Trigger choice honors [AiProfile.
/// blackTriggerBias] (The Gambler takes one regardless of resonance
/// fit; most profiles only bother if it resonates reasonably well for
/// this character; a bias of 0 skips it entirely), and Trigger
/// selection favors [AiProfile.preferredTriggerTags] (see [triggerTags])
/// while still satisfying the Loadout rules (Trion Capacity budget, the
/// equip-count ceiling, and exactly [LoadoutRulesConfig.
/// requiredActiveAbilityCount] active abilities).
///
/// This is a heuristic, not an optimizer - it greedily takes the
/// highest-scoring Triggers that fit, falling back to the cheapest
/// available ones if high scorers don't fit the remaining budget, so
/// that hitting the exact active-ability requirement takes priority
/// over perfectly matching every preferred tag.
class LoadoutBuilder {
  final LoadoutRulesConfig rules;
  final ResonanceGrid resonanceGrid;

  const LoadoutBuilder({
    this.rules = LoadoutRulesConfig.defaults,
    this.resonanceGrid = ResonanceGrid.defaultGrid,
  });

  /// Tags describing what [trigger] is useful for, matched against
  /// [AiProfile.preferredTriggerTags]. Kept close to the Loadout builder
  /// (rather than a general-purpose Trigger field) since these are a
  /// scoring heuristic, not part of the Trigger's own data contract.
  Set<String> triggerTags(ActiveTrigger trigger) {
    final tags = <String>{};
    if (trigger.attackSubtype == AttackSubtype.aoe) tags.add('aoe');
    if (trigger.attackSubtype == AttackSubtype.burst) tags.add('burst');
    // Both the specific band and an umbrella tag, so a profile can prefer
    // "anything at range" (the Sharpshooter) or a single band.
    tags.add(trigger.rangeTag.name);
    if (trigger.rangeTag.isAtRange) tags.add('at_range');
    if (trigger.targetAffiliation == TargetAffiliation.opponent &&
        trigger.inflictedStatusEffects.isNotEmpty) {
      tags.add('debuff');
    }
    if (trigger.healAmount != null) tags.add('heal');
    if (trigger.targetAffiliation != TargetAffiliation.opponent &&
        trigger.inflictedStatusEffects.isNotEmpty) {
      tags.add('buff');
    }
    if (trigger.targetAffiliation == TargetAffiliation.self &&
        trigger.damageType == null) {
      tags.add('defense');
    }
    return tags;
  }

  double _rawDamagePower(ActiveTrigger trigger) {
    final damage = trigger.damage;
    final hits =
        trigger.attackSubtype == AttackSubtype.burst ? trigger.hitsPerUse : 1;
    return damage == null ? 0.0 : damage.average * hits;
  }

  /// Flat score bonus per matched preferred tag. Kept proportionate to
  /// the content catalog's typical single-target damage average (a
  /// meaningful nudge that can still be outweighed by a much
  /// harder-hitting untagged option, not an unconditional override of
  /// raw damage) - re-tune this alongside any future rebalance of the
  /// Trigger catalog's damage magnitudes.
  static const _tagMatchBonus = 200.0;

  double _score(ActiveTrigger trigger, AiProfile profile) {
    final matchedTags =
        triggerTags(trigger).intersection(profile.preferredTriggerTags).length;
    return _rawDamagePower(trigger) + matchedTags * _tagMatchBonus;
  }

  int _resonanceRank(ResonanceGrade grade) => switch (grade) {
        ResonanceGrade.a => 3,
        ResonanceGrade.b => 2,
        ResonanceGrade.c => 1,
        ResonanceGrade.d => 0,
      };

  BlackTrigger? _pickBlackTrigger(
    Character character,
    AiProfile profile,
    Iterable<BlackTrigger> candidates,
    int budget,
  ) {
    if (profile.blackTriggerBias <= 0) return null;
    final affordable =
        candidates.where((bt) => bt.equipCost <= budget).toList();
    if (affordable.isEmpty) return null;

    if (profile.blackTriggerBias >= 0.9) {
      // The Gambler: take one regardless of fit.
      return affordable.first;
    }

    affordable.sort((a, b) =>
        _resonanceRank(resonanceGrid.lookup(character.type, b.type)).compareTo(
            _resonanceRank(resonanceGrid.lookup(character.type, a.type))));
    final best = affordable.first;
    final grade = resonanceGrid.lookup(character.type, best.type);
    if (grade == ResonanceGrade.d) return null;
    return best;
  }

  Loadout build(
    Character character, {
    required Iterable<ActiveTrigger> activeTriggerPool,
    required Iterable<PassiveTrigger> passiveTriggerPool,
    required Iterable<BlackTrigger> blackTriggerPool,
    required AiProfile profile,
  }) {
    final budget = character.baseStats.trionCapacity;
    var spent = 0;
    var itemCount = 0;

    final blackTrigger =
        _pickBlackTrigger(character, profile, blackTriggerPool, budget);
    var requiredActive = rules.requiredActiveAbilityCount -
        (blackTrigger?.activeAbilityCount ?? 0);

    BlackTrigger? finalBlackTrigger = blackTrigger;
    if (blackTrigger != null) {
      spent += blackTrigger.equipCost;
      itemCount++;
    }

    // If including the Black Trigger leaves no room for the required
    // active abilities even with the cheapest ones available, drop it -
    // hitting the exact active-ability count is a hard Loadout rule,
    // resonance fit is only a preference.
    final cheapestActiveCost = activeTriggerPool.isEmpty
        ? 0
        : (activeTriggerPool.map((t) => t.equipCost).toList()..sort()).first;
    if (finalBlackTrigger != null &&
        requiredActive > 0 &&
        budget - spent < cheapestActiveCost * requiredActive) {
      spent -= finalBlackTrigger.equipCost;
      itemCount--;
      finalBlackTrigger = null;
      requiredActive = rules.requiredActiveAbilityCount;
    }

    final chosenActives = <ActiveTrigger>[];
    final scoredActives = activeTriggerPool.toList()
      ..sort((a, b) => _score(b, profile).compareTo(_score(a, profile)));

    // Greedily take the highest-scoring actives, but only if doing so
    // still leaves enough budget to afford (at minimum, the cheapest
    // option for) every remaining required slot - otherwise an early
    // expensive pick can starve later slots and leave the Loadout short
    // of the exact active-ability requirement.
    for (final trigger in scoredActives) {
      if (chosenActives.length >= requiredActive) break;
      if (itemCount >= rules.maxEquippedTriggers) break;
      final slotsAfterThisPick = requiredActive - chosenActives.length - 1;
      final reserveForRemainingSlots = slotsAfterThisPick * cheapestActiveCost;
      if (spent + trigger.equipCost + reserveForRemainingSlots > budget) {
        continue;
      }
      chosenActives.add(trigger);
      spent += trigger.equipCost;
      itemCount++;
    }

    // Fallback pass: if high scorers didn't all fit (e.g. the pool ran
    // out of eligible candidates before reservation math would even
    // apply), fill any remaining required actives with whatever's
    // cheapest among what's left.
    if (chosenActives.length < requiredActive) {
      final remaining = scoredActives
          .where((t) => !chosenActives.contains(t))
          .toList()
        ..sort((a, b) => a.equipCost.compareTo(b.equipCost));
      for (final trigger in remaining) {
        if (chosenActives.length >= requiredActive) break;
        if (itemCount >= rules.maxEquippedTriggers) break;
        if (spent + trigger.equipCost > budget) continue;
        chosenActives.add(trigger);
        spent += trigger.equipCost;
        itemCount++;
      }
    }

    // A heavily support/defense-tagged profile can otherwise end up with
    // almost no damage-dealing actives at all (every non-damage option
    // scores higher purely from the preferred-tag bonus, which dwarfs any
    // realistic damage average) - leaving that character with too few
    // ways to ever meaningfully contribute to a kill, no matter how
    // strong the content's damage numbers are. Guarantee at least half of
    // the chosen actives are damage-capable (a Black Trigger's own active
    // abilities count towards this), swapping out the worst-scoring
    // non-damage picks for the hardest-hitting damage candidates still
    // available - by raw damage power, not the tag-boosted `_score`,
    // since the point is restoring real throughput, not just picking
    // whichever attack happens to also carry a preferred tag (e.g. a
    // drain Trigger tagged 'heal').
    final blackTriggerDamageCount = finalBlackTrigger?.activeAbilities
            .where((a) => a.damageType != null)
            .length ??
        0;
    final minDamageActives = ((rules.requiredActiveAbilityCount / 2).ceil() -
            blackTriggerDamageCount)
        .clamp(0, chosenActives.length);

    int damageActiveCount() =>
        chosenActives.where((t) => t.damageType != null).length;

    if (damageActiveCount() < minDamageActives) {
      final damageCandidatesByPower = scoredActives
          .where((t) => t.damageType != null && !chosenActives.contains(t))
          .toList()
        ..sort((a, b) => _rawDamagePower(b).compareTo(_rawDamagePower(a)));

      for (final replacement in damageCandidatesByPower) {
        if (damageActiveCount() >= minDamageActives) break;
        final nonDamageByWorstFirst = chosenActives
            .where((t) => t.damageType == null)
            .toList()
          ..sort((a, b) => _score(a, profile).compareTo(_score(b, profile)));
        for (final toRemove in nonDamageByWorstFirst) {
          if (spent - toRemove.equipCost + replacement.equipCost <= budget) {
            chosenActives.remove(toRemove);
            chosenActives.add(replacement);
            spent = spent - toRemove.equipCost + replacement.equipCost;
            break;
          }
        }
      }
    }

    final chosenPassives = <PassiveTrigger>[];
    final scoredPassives = passiveTriggerPool.toList()
      ..sort((a, b) => a.equipCost.compareTo(b.equipCost));
    for (final trigger in scoredPassives) {
      if (itemCount >= rules.maxEquippedTriggers) break;
      if (spent + trigger.equipCost > budget) continue;
      chosenPassives.add(trigger);
      spent += trigger.equipCost;
      itemCount++;
    }

    return Loadout(
      characterId: character.id,
      triggers: [...chosenActives, ...chosenPassives],
      blackTrigger: finalBlackTrigger,
    );
  }
}
