import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

void main() {
  group('SceneNode JSON round-tripping', () {
    test('DialogueNode', () {
      const node = DialogueNode(
        id: 'd1',
        speaker: 'Hero',
        text: 'Hello there.',
        sprite: 'hero_smile.png',
        background: 'town_square.png',
        next: 'd2',
      );
      final restored = SceneNode.fromJson(node.toJson()) as DialogueNode;

      expect(restored.id, node.id);
      expect(restored.speaker, node.speaker);
      expect(restored.text, node.text);
      expect(restored.sprite, node.sprite);
      expect(restored.background, node.background);
      expect(restored.next, node.next);
    });

    test('DialogueNode with a null next (scene-ending line)', () {
      const node = DialogueNode(id: 'd1', text: 'The end.');
      final restored = SceneNode.fromJson(node.toJson()) as DialogueNode;
      expect(restored.next, isNull);
      expect(restored.speaker, isNull);
    });

    test('ChoiceNode', () {
      const node = ChoiceNode(
        id: 'c1',
        prompt: 'What do you do?',
        choices: [
          SceneChoice(text: 'Fight', next: 'battle1'),
          SceneChoice(text: 'Flee', next: 'd3'),
        ],
      );
      final restored = SceneNode.fromJson(node.toJson()) as ChoiceNode;

      expect(restored.id, node.id);
      expect(restored.prompt, node.prompt);
      expect(restored.choices, hasLength(2));
      expect(restored.choices[0].text, 'Fight');
      expect(restored.choices[0].next, 'battle1');
      expect(restored.choices[1].text, 'Flee');
      expect(restored.choices[1].next, 'd3');
    });

    test('BattleTriggerNode', () {
      const node = BattleTriggerNode(
        id: 'b1',
        battleId: 'boss-fight-1',
        onTeamAWinsNext: 'd-victory',
        onTeamBWinsNext: 'd-defeat',
        onDrawNext: 'd-draw',
      );
      final restored = SceneNode.fromJson(node.toJson()) as BattleTriggerNode;

      expect(restored.id, node.id);
      expect(restored.battleId, node.battleId);
      expect(restored.onTeamAWinsNext, node.onTeamAWinsNext);
      expect(restored.onTeamBWinsNext, node.onTeamBWinsNext);
      expect(restored.onDrawNext, node.onDrawNext);
    });

    test('EndNode', () {
      const node = EndNode(id: 'e1');
      final restored = SceneNode.fromJson(node.toJson());
      expect(restored, isA<EndNode>());
      expect(restored.id, 'e1');
    });

    test('an unknown type discriminator throws', () {
      expect(
        () => SceneNode.fromJson({'type': 'mystery', 'id': 'x'}),
        throwsArgumentError,
      );
    });
  });

  group('Scene JSON round-tripping', () {
    test('deserializes a full scene graph and looks up nodes by id', () {
      final json = {
        'id': 'scene-1',
        'startNodeId': 'd1',
        'nodes': [
          {
            'type': 'dialogue',
            'id': 'd1',
            'text': 'A wild encounter appears!',
            'next': 'b1',
          },
          {
            'type': 'battleTrigger',
            'id': 'b1',
            'battleId': 'random-encounter',
            'onTeamAWinsNext': 'd2',
          },
          {
            'type': 'dialogue',
            'id': 'd2',
            'text': 'You won!',
          },
        ],
      };

      final scene = Scene.fromJson(json);

      expect(scene.id, 'scene-1');
      expect(scene.startNodeId, 'd1');
      expect(scene.startNode, isA<DialogueNode>());
      expect(scene['b1'], isA<BattleTriggerNode>());
      expect(scene['d2'], isA<DialogueNode>());
    });

    test('looking up a missing node id throws', () {
      final scene = Scene(
        id: 'scene-1',
        startNodeId: 'd1',
        nodesById: const {'d1': DialogueNode(id: 'd1', text: 'Hi')},
      );
      expect(() => scene['missing'], throwsArgumentError);
    });

    test('Scene.toJson round-trips through Scene.fromJson', () {
      final scene = Scene(
        id: 'scene-1',
        startNodeId: 'd1',
        nodesById: const {
          'd1': DialogueNode(id: 'd1', text: 'Hi', next: 'end'),
          'end': EndNode(id: 'end'),
        },
      );

      final restored = Scene.fromJson(scene.toJson());
      expect(restored.id, scene.id);
      expect(restored.startNodeId, scene.startNodeId);
      expect(restored.nodesById.keys.toSet(), scene.nodesById.keys.toSet());
    });
  });
}
