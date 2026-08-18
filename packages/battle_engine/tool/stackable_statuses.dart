import 'package:battle_engine/battle_engine.dart';

/// Which status effects should stack, and which should only refresh.
///
/// The test is whether a second copy means anything coherent. A number that
/// adds (bleed damage, a flat stat step) stacks cleanly and reads as "x2". A
/// switch that is either on or off (cannot act) has nothing to add. A
/// multiplier compounds, and a per-remaining-turn modifier already scales with
/// its own duration, so both double-count if stacked.
void main() {
  final catalog = StatusEffectCatalog.defaultCatalog;

  final stack = <String, String>{};
  final refresh = <String, String>{};

  for (final def in catalog.all) {
    final reasons = <String>[];

    final isLockout = def.preventsActions ||
        def.preventsReposition ||
        def.preventsTargeting ||
        def.preventsHealing ||
        def.preventsAllyInteraction ||
        def.cannotTargetSource ||
        def.forcesNextAttackMiss ||
        def.forcesRepetitionOfLastAbility ||
        def.locksRandomAbilityEachTurn ||
        def.locksOriginFromData ||
        def.rangedTargetsReducedByOne ||
        def.sourceHasAdvantageAgainstTarget;
    final isMultiplier = def.outgoingDamageMultiplier != null ||
        def.allDamageTakenMultiplier != null ||
        def.trionCostMultiplier != null ||
        def.repeatAbilityDamageMultiplier != null ||
        def.misfireChance != null;
    final isPerTurnScaled = def.perRemainingTurnStatModifiers.isNotEmpty;
    final hasInstanceState = def.vulnerableToRandomDamageTypesCount != null ||
        def.locksRandomAbilityEachTurn ||
        def.damageTypeInteractions.isNotEmpty;
    final isFlatStat = def.flatStatModifiers.isNotEmpty;
    final isTick = def.turnStartDamage != null ||
        def.turnStartHeal != null ||
        def.trionCapacityDrainPercentToCauser != null;
    final isZeroing = def.zeroedStats.isNotEmpty;

    if (isTick) reasons.add('a tick that adds');
    if (isFlatStat && !isPerTurnScaled) reasons.add('a flat stat step');

    final blockers = <String>[];
    if (isLockout) blockers.add('an on/off lockout');
    if (isMultiplier) blockers.add('a multiplier that would compound');
    if (isPerTurnScaled) blockers.add('already scales with its own duration');
    if (hasInstanceState) blockers.add('carries per-instance state');
    if (isZeroing) blockers.add('already zeroes the stat');

    if (reasons.isNotEmpty && blockers.isEmpty) {
      stack[def.name] = reasons.join(' and ');
    } else {
      refresh[def.name] =
          blockers.isEmpty ? 'nothing to add a second copy of' : blockers.first;
    }
  }

  print('SHOULD STACK (${stack.length})');
  final stackKeys = stack.keys.toList()..sort();
  for (final k in stackKeys) {
    print('  ${k.padRight(22)} ${stack[k]}');
  }

  print('\nSHOULD REFRESH ONLY (${refresh.length})');
  final byReason = <String, List<String>>{};
  for (final e in refresh.entries) {
    byReason.putIfAbsent(e.value, () => []).add(e.key);
  }
  final reasonKeys = byReason.keys.toList()..sort();
  for (final r in reasonKeys) {
    final names = byReason[r]!..sort();
    print('  $r (${names.length})');
    print('    ${names.join(', ')}');
  }
}
