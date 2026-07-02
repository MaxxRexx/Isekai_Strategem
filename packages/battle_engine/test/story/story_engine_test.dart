import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

Scene _scene({List<SceneNode>? nodes, String startNodeId = 'd1'}) {
  final list = nodes ??
      const [
        DialogueNode(id: 'd1', text: 'Hello.', next: 'c1'),
        ChoiceNode(id: 'c1', choices: [
          SceneChoice(text: 'Fight', next: 'b1'),
          SceneChoice(text: 'Talk', next: 'd2'),
        ]),
        BattleTriggerNode(
          id: 'b1',
          battleId: 'fight-1',
          onTeamAWinsNext: 'd-victory',
          onTeamBWinsNext: 'd-defeat',
          onDrawNext: 'd-draw',
        ),
        DialogueNode(id: 'd2', text: 'They talk it out.'),
        DialogueNode(id: 'd-victory', text: 'You won!'),
        DialogueNode(id: 'd-defeat', text: 'You lost.'),
        DialogueNode(id: 'd-draw', text: 'A tie.'),
      ];
  return Scene(
    id: 'scene-1',
    startNodeId: startNodeId,
    nodesById: {for (final n in list) n.id: n},
  );
}

void main() {
  group('StoryEngine', () {
    test('starts on the scene\'s startNode', () {
      final engine = StoryEngine(_scene());
      final step = engine.currentStep;
      expect(step, isA<AwaitingAdvance>());
      expect((step as AwaitingAdvance).node.id, 'd1');
      expect(engine.isEnded, isFalse);
    });

    test('advance() moves to the DialogueNode\'s next node', () {
      final engine = StoryEngine(_scene());
      engine.advance();
      expect(engine.currentStep, isA<AwaitingChoice>());
    });

    test('advance() with a null next ends the scene', () {
      final engine = StoryEngine(_scene());
      engine.advance(); // d1 -> c1
      engine.choose(1); // c1 -> d2 (no next)
      engine.advance(); // d2 -> ends
      expect(engine.isEnded, isTrue);
      expect(engine.currentStep, isA<SceneEnded>());
    });

    test('advance() throws when not awaiting a DialogueNode', () {
      final engine = StoryEngine(_scene());
      engine.advance(); // now on the ChoiceNode
      expect(() => engine.advance(), throwsStateError);
    });

    test('choose() moves to the chosen option\'s target node', () {
      final engine = StoryEngine(_scene());
      engine.advance(); // -> c1
      engine.choose(0); // -> b1
      expect(engine.currentStep, isA<AwaitingBattleResolution>());
      expect((engine.currentStep as AwaitingBattleResolution).node.battleId,
          'fight-1');
    });

    test('choose() throws for an out-of-range index', () {
      final engine = StoryEngine(_scene());
      engine.advance(); // -> c1
      expect(() => engine.choose(5), throwsRangeError);
    });

    test('choose() throws when not awaiting a ChoiceNode', () {
      final engine = StoryEngine(_scene());
      expect(() => engine.choose(0), throwsStateError);
    });

    test('resolveBattle() routes to onTeamAWinsNext on a team A win', () {
      final engine = StoryEngine(_scene());
      engine.advance();
      engine.choose(0); // -> battle trigger
      engine.resolveBattle(BattleOutcome.teamAWins);
      expect(engine.currentStep, isA<AwaitingAdvance>());
      expect((engine.currentStep as AwaitingAdvance).node.id, 'd-victory');
    });

    test('resolveBattle() routes to onTeamBWinsNext on a team B win', () {
      final engine = StoryEngine(_scene());
      engine.advance();
      engine.choose(0);
      engine.resolveBattle(BattleOutcome.teamBWins);
      expect((engine.currentStep as AwaitingAdvance).node.id, 'd-defeat');
    });

    test('resolveBattle() routes to onDrawNext on a draw', () {
      final engine = StoryEngine(_scene());
      engine.advance();
      engine.choose(0);
      engine.resolveBattle(BattleOutcome.draw);
      expect((engine.currentStep as AwaitingAdvance).node.id, 'd-draw');
    });

    test('resolveBattle() ends the scene when the matching next id is unset',
        () {
      final scene = _scene(nodes: const [
        DialogueNode(id: 'd1', text: 'Hi.', next: 'b1'),
        BattleTriggerNode(id: 'b1', battleId: 'fight-1'),
      ]);
      final engine = StoryEngine(scene);
      engine.advance(); // -> b1
      engine.resolveBattle(BattleOutcome.teamAWins);
      expect(engine.isEnded, isTrue);
    });

    test('resolveBattle() throws for BattleOutcome.ongoing', () {
      final engine = StoryEngine(_scene());
      engine.advance();
      engine.choose(0);
      expect(() => engine.resolveBattle(BattleOutcome.ongoing),
          throwsArgumentError);
    });

    test('resolveBattle() throws when not awaiting a BattleTriggerNode', () {
      final engine = StoryEngine(_scene());
      expect(() => engine.resolveBattle(BattleOutcome.teamAWins),
          throwsStateError);
    });

    test('a scene starting directly on an EndNode is immediately ended', () {
      final scene = _scene(
        nodes: const [EndNode(id: 'e1')],
        startNodeId: 'e1',
      );
      final engine = StoryEngine(scene);
      expect(engine.isEnded, isTrue);
    });
  });
}
