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

  test('a stranded squad walks into firing position within two turns', () {
    // The hardest case the walk-towards-the-band fallback has to solve, and
    // 1b makes it the *only* two-step case: both squads camped on their back
    // lines. Nothing is in band from there or from one step in, so the
    // strict-improvement test can never fire and only the shortfall fallback
    // gets them there.
    //
    // A screened formation cannot strand anyone longer than this, because the
    // bodies doing the screening are themselves standing further forward and
    // are therefore the easiest thing on the board to reach. Screening hides
    // the target behind the squad; it never hides the squad.
    final battle = battleWith(
      triggers: closeOnly,
      aLine: BattlePosition.back,
      bLine: BattlePosition.back,
    );
    final ai = ProfileDrivenAi(AiProfile.theExecutioner,
        random: const _NoMistakes());
    final mine = [for (final c in battle.teamA.characters) battle.states[c.id]!];
    final opponents = [
      for (final c in battle.teamB.characters) battle.states[c.id]!,
    ];

    bool anyoneCanShoot() => mine.any((state) =>
        battle.turnEngine.reachableAbilityCount(
            state, state.position, closeOnly, opponents) >
        0);

    expect(anyoneCanShoot(), isFalse, reason: 'they start stranded at 4');

    for (var turn = 0; turn < 2; turn++) {
      final plan = ai.planTurn(battle,
          equippedActiveTriggers: equipAll(battle, closeOnly));
      for (final move in plan.where((a) => a.isReposition)) {
        battle.turnEngine
            .reposition(battle.states[move.characterId]!, move.destination!);
      }
      for (final state in mine) {
        state.endTurn();
      }
    }

    expect(anyoneCanShoot(), isTrue,
        reason: 'two steps must be enough to bring a Close kit to bear, or a '
            'stranded squad would stall the battle out');
  });

  test('a screen never strands you, because the screens are themselves the '
      'nearest targets', () {
    // Their sniper is behind two bodies and unreachable by a knife. Those two
    // bodies are standing on their front line, which is the closest thing on
    // the board, so a Close kit always has something to hit.
    final battle = battleWith(
      triggers: closeOnly,
      aLine: BattlePosition.front,
      bLine: BattlePosition.front,
    );
    final theirs = battle.teamB.characters;
    battle.states[theirs[2].id]!.position = BattlePosition.back;
    final attacker = battle.states[battle.teamA.characters.first.id]!;
    final sniper = battle.states[theirs[2].id]!;
    final opponents = [for (final c in theirs) battle.states[c.id]!];

    expect(battle.turnEngine.distanceBetween(attacker, sniper), 4,
        reason: 'two screens put the sniper out of every band but Long');
    expect(
      battle.turnEngine.reachableAbilityCount(
          attacker, attacker.position, closeOnly, opponents),
      1,
      reason: 'the screens themselves are at distance 0 and always hittable',
    );
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
    // Back against middle is distance 3: the Long Range Trigger reaches, the
    // two Close Range ones do not, Close being 0-2 after 1b. Stepping in makes
    // it 2 and flips both, and FAT means the step does not cost the whole
    // turn. Their squad stacks on one line, so nobody screens anybody and the
    // arithmetic stays about the two lines alone.
    final mixed = [
      testTrigger(id: 'close-a', rangeTag: RangeTag.close, trionCost: 5),
      testTrigger(id: 'close-b', rangeTag: RangeTag.close, trionCost: 5),
      testTrigger(id: 'long-a', rangeTag: RangeTag.long, trionCost: 5),
    ];
    final battle = battleWith(
      triggers: mixed,
      aLine: BattlePosition.back,
      bLine: BattlePosition.middle,
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
      bLine: BattlePosition.middle,
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
        final theirLines = [
          for (final c in battle.teamB.characters)
            if (battle.states[c.id]!.isAlive) battle.states[c.id]!.position,
        ];
        expect(
          trigger.rangeTag.reaches(BattleDistance.betweenEnemies(
              move.destination!, battle.states[targetId]!.position,
              targetSquad: theirLines)),
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
      bLine: BattlePosition.middle,
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

  test('a self-buff does not disguise a character who can reach nothing', () {
    // The reported stall: two squads out of range of each other, each holding
    // a self-buff, standing still and re-buffing for the rest of the battle.
    // A buff reaches from anywhere, so counting it as "reachable" meant nobody
    // ever registered as stuck.
    final closeAndBuff = [
      testTrigger(id: 'close-hit', rangeTag: RangeTag.close, trionCost: 5),
      testTrigger(
        id: 'self-buff',
        rangeTag: RangeTag.close,
        targetAffiliation: TargetAffiliation.self,
        includeDamage: false,
        inflictedStatusEffects: const [StatusEffectApplication('empowered')],
      ),
    ];
    final battle = battleWith(
      triggers: closeAndBuff,
      aLine: BattlePosition.back,
      bLine: BattlePosition.back,
    );

    expect(
      battle.turnEngine.reachableAbilityCount(
        battle.states['a-1']!,
        BattlePosition.back,
        closeAndBuff,
        battle.teamB.characters.map((c) => battle.states[c.id]!).toList(),
      ),
      0,
      reason: 'only what can be aimed at an enemy counts',
    );

    final ai = ProfileDrivenAi(AiProfile.theExecutioner,
        random: const _NoMistakes());
    final plan = ai.planTurn(battle,
        equippedActiveTriggers: equipAll(battle, closeAndBuff));

    expect(plan.where((a) => a.isReposition), isNotEmpty,
        reason: 'having a buff to spam is not a reason to stand still');
  });
}
