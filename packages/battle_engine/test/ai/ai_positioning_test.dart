import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// A [Random] that never rolls a mistake, so the AI's intended choice is the
/// one under test.
class _NoMistakes implements Random {
  const _NoMistakes();
  @override
  double nextDouble() => 1.0;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

Team _team(String prefix) => Team(
      id: '$prefix-team',
      characters: [
        testCharacter(id: '$prefix-1'),
        testCharacter(id: '$prefix-2'),
        testCharacter(id: '$prefix-3'),
      ],
    );

/// #1 (range bands), AI side: the opponent reads the board it is standing on.
/// It picks targets its bands actually reach, and it moves when the position
/// is the thing stopping it.
void main() {
  Battle battleWith({
    required List<ActiveTrigger> triggers,
    required BattlePosition aLine,
    required BattlePosition bLine,
  }) {
    final battle = Battle(teamA: _team('a'), teamB: _team('b'));
    battle.teamA.trionPool.gain(1000);
    battle.teamB.trionPool.gain(1000);
    for (final c in battle.teamA.characters) {
      battle.states[c.id]!.position = aLine;
    }
    for (final c in battle.teamB.characters) {
      battle.states[c.id]!.position = bLine;
    }
    return battle;
  }

  Map<String, List<ActiveTrigger>> equipAll(
    Battle battle,
    List<ActiveTrigger> triggers,
  ) =>
      {
        for (final c in [
          ...battle.teamA.characters,
          ...battle.teamB.characters,
        ])
          c.id: triggers,
      };

  final closeOnly = [
    testTrigger(id: 'close-hit', rangeTag: RangeTag.close, trionCost: 5),
  ];

  test('the AI does not aim an ability past its band', () {
    // Both squads on their back lines: distance 4, well outside Close Range.
    final battle = battleWith(
      triggers: closeOnly,
      aLine: BattlePosition.back,
      bLine: BattlePosition.back,
    );
    final ai = ProfileDrivenAi(AiProfile.theExecutioner,
        random: const _NoMistakes());

    final plan = ai.planTurn(battle,
        equippedActiveTriggers: equipAll(battle, closeOnly));

    expect(plan.where((a) => !a.isReposition), isEmpty,
        reason: 'nothing is inside the band, so nothing is aimed');
  });

  test('a character who can reach nothing plans a step instead', () {
    final battle = battleWith(
      triggers: closeOnly,
      aLine: BattlePosition.back,
      bLine: BattlePosition.back,
    );
    final ai = ProfileDrivenAi(AiProfile.theExecutioner,
        random: const _NoMistakes());

    final plan = ai.planTurn(battle,
        equippedActiveTriggers: equipAll(battle, closeOnly));

    final moves = plan.where((a) => a.isReposition).toList();
    expect(moves, hasLength(3), reason: 'all three are stranded');
    for (final move in moves) {
      expect(move.destination, BattlePosition.middle,
          reason: 'one step towards the enemy, not a teleport');
    }
  });

  test('a planned step is resolvable and lands the character on the line', () {
    final battle = battleWith(
      triggers: closeOnly,
      aLine: BattlePosition.back,
      bLine: BattlePosition.back,
    );
    final ai = ProfileDrivenAi(AiProfile.theExecutioner,
        random: const _NoMistakes());

    final plan = ai.planTurn(battle,
        equippedActiveTriggers: equipAll(battle, closeOnly));
    for (final move in plan.where((a) => a.isReposition)) {
      expect(
        battle.turnEngine
            .reposition(battle.states[move.characterId]!, move.destination!),
        isTrue,
      );
    }

    for (final c in battle.teamA.characters) {
      expect(battle.states[c.id]!.position, BattlePosition.middle);
    }
  });

  test('with one action and something to do, the AI swings instead of moving',
      () {
    // Distance 1: Close Range reaches, so there is no reason to spend the
    // turn walking.
    final battle = battleWith(
      triggers: closeOnly,
      aLine: BattlePosition.front,
      bLine: BattlePosition.middle,
    );
    final ai = ProfileDrivenAi(AiProfile.theExecutioner,
        random: const _NoMistakes());

    final plan = ai.planTurn(battle,
        equippedActiveTriggers: equipAll(battle, closeOnly));

    expect(plan.where((a) => a.isReposition), isEmpty);
    expect(plan.where((a) => !a.isReposition), isNotEmpty);
  });

  test('a spare ability use buys the step that brings more Triggers to bear',
      () {
    // Back against front is distance 2: the Long Range Trigger reaches, the
    // two Close Range ones do not. Stepping in flips two of the three into
    // band, and FAT means the step does not cost the whole turn.
    final mixed = [
      testTrigger(id: 'close-a', rangeTag: RangeTag.close, trionCost: 5),
      testTrigger(id: 'close-b', rangeTag: RangeTag.close, trionCost: 5),
      testTrigger(id: 'long-a', rangeTag: RangeTag.long, trionCost: 5),
    ];
    final battle = battleWith(
      triggers: mixed,
      aLine: BattlePosition.back,
      bLine: BattlePosition.front,
    );
    for (final c in battle.teamA.characters) {
      battle.states[c.id]!.fatTriggeredThisTurn = true;
    }
    final ai = ProfileDrivenAi(AiProfile.theExecutioner,
        random: const _NoMistakes());

    final plan = ai.planTurn(battle, equippedActiveTriggers: equipAll(battle, mixed));

    final moves = plan.where((a) => a.isReposition).toList();
    expect(moves, isNotEmpty,
        reason: 'a spare use makes closing the gap cheap enough to be worth it');
    expect(moves.first.destination, BattlePosition.middle);
  });

  test('after a planned step, the AI aims from where it will be standing', () {
    final mixed = [
      testTrigger(id: 'close-a', rangeTag: RangeTag.close, trionCost: 5),
      testTrigger(id: 'close-b', rangeTag: RangeTag.close, trionCost: 5),
      testTrigger(id: 'long-a', rangeTag: RangeTag.long, trionCost: 5),
    ];
    final battle = battleWith(
      triggers: mixed,
      aLine: BattlePosition.back,
      bLine: BattlePosition.front,
    );
    for (final c in battle.teamA.characters) {
      battle.states[c.id]!.fatTriggeredThisTurn = true;
    }
    final ai = ProfileDrivenAi(AiProfile.theExecutioner,
        random: const _NoMistakes());

    final plan = ai.planTurn(battle, equippedActiveTriggers: equipAll(battle, mixed));

    // Whatever it aims after the move must be legal from the destination, not
    // from where it started. That is the whole point of planning the step
    // first: move then strike, in one turn.
    for (final action in plan.where((a) => !a.isReposition)) {
      final move = plan.firstWhere(
        (m) => m.isReposition && m.characterId == action.characterId,
        orElse: () => action,
      );
      if (!move.isReposition) continue;
      final trigger = mixed.firstWhere((t) => t.id == action.triggerId);
      for (final targetId in action.targetIds) {
        expect(
          trigger.rangeTag.reaches(BattleDistance.betweenEnemies(
              move.destination!, battle.states[targetId]!.position)),
          isTrue,
          reason: '${action.triggerId} must reach from ${move.destination}',
        );
      }
    }
  });

  test('takeTurn moves before it swings, so a step still leaves an action',
      () {
    // Back against front (distance 2) with FAT: the AI should close and then
    // use its Close Range Triggers in the same turn.
    final mixed = [
      testTrigger(id: 'close-a', rangeTag: RangeTag.close, trionCost: 5),
      testTrigger(id: 'close-b', rangeTag: RangeTag.close, trionCost: 5),
      testTrigger(id: 'long-a', rangeTag: RangeTag.long, trionCost: 5),
    ];
    final battle = battleWith(
      triggers: mixed,
      aLine: BattlePosition.back,
      bLine: BattlePosition.front,
    );
    for (final c in battle.teamA.characters) {
      battle.states[c.id]!.fatTriggeredThisTurn = true;
    }
    final ai = ProfileDrivenAi(AiProfile.theExecutioner,
        random: const _NoMistakes());

    final results =
        ai.takeTurn(battle, equippedActiveTriggers: equipAll(battle, mixed));

    expect(battle.states['a-1']!.position, BattlePosition.middle);
    expect(results.where((r) => r.characterId == 'a-1'), isNotEmpty,
        reason: 'the move used one of three uses, not the whole turn');
  });
}
