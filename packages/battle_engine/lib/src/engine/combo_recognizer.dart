import '../models/combo.dart';
import '../models/trigger.dart';
import 'character_battle_state.dart';

/// Combat-v2 Phase I. A per-turn rolling record of resolved actions, the
/// memory the [ComboRecognizer] reads. Extends the thin per-character
/// history (`lastUsedTriggerId` / `triggersUsedThisTurn`) into a
/// battle-level, cross-character, ordered log with targets and applied
/// statuses. Bounded (cleared each turn) and cheap.
class ComboLedger {
  final List<ComboLedgerEntry> _entries = [];
  int _nextSequence = 0;

  /// All actions recorded so far this turn, in resolution order.
  List<ComboLedgerEntry> get entries => List.unmodifiable(_entries);

  /// Records one resolved action and returns the entry (with its assigned
  /// sequence). Callers pass the already-known facts about the action; the
  /// ledger only assigns ordering.
  ComboLedgerEntry record({
    required String actorId,
    required String teamId,
    required ActiveTrigger trigger,
    required List<String> targetIds,
    required List<String> statusesApplied,
    required bool dealtDamage,
  }) {
    final entry = ComboLedgerEntry(
      actorId: actorId,
      teamId: teamId,
      triggerId: trigger.id,
      originTag: trigger.originTag,
      abilityType: trigger.abilityType,
      abilitySubtype: trigger.abilitySubtype,
      targetAffiliation: trigger.targetAffiliation,
      targetIds: List.of(targetIds),
      statusesApplied: List.of(statusesApplied),
      dealtDamage: dealtDamage,
      sequence: _nextSequence++,
    );
    _entries.add(entry);
    return entry;
  }

  /// Clears the log at a turn boundary (combos never span turns under
  /// alternating resolution).
  void clearTurn() {
    _entries.clear();
    _nextSequence = 0;
  }

  /// Builds the [ComboContext] for [payoff] against this ledger: the
  /// same-team actions that resolved before it, plus a snapshot of the
  /// payoff's primary target ([targetState], when known) for status- and
  /// hp-gated combos.
  ComboContext contextFor(
    ComboLedgerEntry payoff, {
    CharacterBattleState? targetState,
  }) {
    final prior = _entries
        .where((e) =>
            e.sequence < payoff.sequence && e.teamId == payoff.teamId)
        .toList();
    final statusIds = <String>{
      if (targetState != null)
        for (final s in targetState.statusEffects) s.definitionId,
    };
    var hpFraction = 1.0;
    if (targetState != null) {
      final max = targetState.character.baseStats.maxHealth;
      if (max > 0) {
        hpFraction = (targetState.currentHealth / max).clamp(0.0, 1.0);
      }
    }
    return ComboContext(
      payoff: payoff,
      priorSameTeamActions: prior,
      targetStatusIds: statusIds,
      targetHpFraction: hpFraction,
    );
  }
}

/// Matches a payoff against a fixed catalog of [ComboDefinition]s. Pure and
/// deterministic: same context in, same recognized combos out.
class ComboRecognizer {
  final List<ComboDefinition> catalog;
  const ComboRecognizer(this.catalog);

  /// Every combo whose condition matches [ctx], strongest first.
  List<RecognizedCombo> recognize(ComboContext ctx) {
    final matched = <RecognizedCombo>[
      for (final def in catalog)
        if (def.condition.matches(ctx)) RecognizedCombo(def),
    ];
    matched.sort((a, b) => b.strength.compareTo(a.strength));
    return matched;
  }

  /// The single strongest matching combo, or null if none matched. Ties
  /// break by catalog order (stable), so recognition stays deterministic.
  RecognizedCombo? best(ComboContext ctx) {
    RecognizedCombo? top;
    for (final def in catalog) {
      if (!def.condition.matches(ctx)) continue;
      if (top == null || def.strength > top.strength) {
        top = RecognizedCombo(def);
      }
    }
    return top;
  }
}
