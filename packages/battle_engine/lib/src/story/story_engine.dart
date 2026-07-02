import '../engine/battle.dart';
import 'scene.dart';
import 'scene_node.dart';

/// What a [StoryEngine] is currently waiting on, derived from the current
/// node's type. The host app/UI switches on this to know which
/// `StoryEngine` method it's allowed to call next.
sealed class StoryStep {
  const StoryStep();
}

/// Waiting on [StoryEngine.advance] to move past [node].
class AwaitingAdvance extends StoryStep {
  final DialogueNode node;
  const AwaitingAdvance(this.node);
}

/// Waiting on [StoryEngine.choose] to pick one of [node]'s choices.
class AwaitingChoice extends StoryStep {
  final ChoiceNode node;
  const AwaitingChoice(this.node);
}

/// Waiting on the host app to run the battle identified by
/// [node.battleId] externally, then call [StoryEngine.resolveBattle]
/// with its outcome.
class AwaitingBattleResolution extends StoryStep {
  final BattleTriggerNode node;
  const AwaitingBattleResolution(this.node);
}

/// The scene has no more nodes to visit.
class SceneEnded extends StoryStep {
  const SceneEnded();
}

/// Steps through a [Scene]'s node graph one node at a time, mirroring how
/// `TurnEngine` drives battle mechanics without owning any UI: this
/// engine only tracks "where in the scene are we and what's next", not
/// how dialogue/choices are rendered or how a triggered battle is
/// actually played out (that's `Battle`'s job, invoked externally by the
/// host app - see [AwaitingBattleResolution]).
class StoryEngine {
  final Scene scene;
  SceneNode? _currentNode;

  StoryEngine(this.scene) : _currentNode = scene.startNode;

  /// What the engine is currently waiting on. Null [_currentNode] (after
  /// the scene ends) always yields [SceneEnded].
  StoryStep get currentStep {
    final node = _currentNode;
    return switch (node) {
      null => const SceneEnded(),
      DialogueNode() => AwaitingAdvance(node),
      ChoiceNode() => AwaitingChoice(node),
      BattleTriggerNode() => AwaitingBattleResolution(node),
      EndNode() => const SceneEnded(),
    };
  }

  bool get isEnded => currentStep is SceneEnded;

  /// Advances past the current [DialogueNode] to its `next` node (or ends
  /// the scene if `next` is null). Throws a [StateError] if the current
  /// node isn't a [DialogueNode].
  void advance() {
    final node = _currentNode;
    if (node is! DialogueNode) {
      throw StateError(
          'advance() called while awaiting ${currentStep.runtimeType}, not a DialogueNode');
    }
    _goTo(node.next);
  }

  /// Picks choice [index] on the current [ChoiceNode], moving to its
  /// target node. Throws a [StateError] if the current node isn't a
  /// [ChoiceNode], or a [RangeError] if [index] is out of range.
  void choose(int index) {
    final node = _currentNode;
    if (node is! ChoiceNode) {
      throw StateError(
          'choose() called while awaiting ${currentStep.runtimeType}, not a ChoiceNode');
    }
    if (index < 0 || index >= node.choices.length) {
      throw RangeError.index(index, node.choices, 'index');
    }
    _goTo(node.choices[index].next);
  }

  /// Reports the outcome of the battle triggered by the current
  /// [BattleTriggerNode], routing to whichever `on*Next` id matches
  /// [outcome] (or ending the scene if that id is null/unset).
  /// [BattleOutcome.ongoing] is never a valid outcome to report here -
  /// only call this once the battle has actually concluded. Throws a
  /// [StateError] if the current node isn't a [BattleTriggerNode].
  void resolveBattle(BattleOutcome outcome) {
    final node = _currentNode;
    if (node is! BattleTriggerNode) {
      throw StateError(
          'resolveBattle() called while awaiting ${currentStep.runtimeType}, not a BattleTriggerNode');
    }
    final next = switch (outcome) {
      BattleOutcome.teamAWins => node.onTeamAWinsNext,
      BattleOutcome.teamBWins => node.onTeamBWinsNext,
      BattleOutcome.draw => node.onDrawNext,
      BattleOutcome.ongoing => throw ArgumentError(
          'resolveBattle called with BattleOutcome.ongoing - the battle '
          'must have actually concluded'),
    };
    _goTo(next);
  }

  void _goTo(String? nodeId) {
    _currentNode = nodeId == null ? null : scene[nodeId];
  }
}
