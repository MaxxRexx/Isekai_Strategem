/// A single node in a [Scene]'s script graph. Sealed so the engine
/// (`StoryEngine`) can exhaustively switch on the concrete type rather
/// than reading a loosely-typed "kind" field at every use site.
sealed class SceneNode {
  final String id;
  const SceneNode({required this.id});

  Map<String, dynamic> toJson();

  /// Dispatches on the JSON `type` discriminator to the right subclass's
  /// `fromJson`.
  factory SceneNode.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'dialogue':
        return DialogueNode.fromJson(json);
      case 'choice':
        return ChoiceNode.fromJson(json);
      case 'battleTrigger':
        return BattleTriggerNode.fromJson(json);
      case 'end':
        return EndNode.fromJson(json);
      default:
        throw ArgumentError('Unknown SceneNode type: $type');
    }
  }
}

/// A single line of dialogue/narration. [next] is the id of the node to
/// advance to, or null to end the scene after this line.
class DialogueNode extends SceneNode {
  /// Null for narration with no speaking character.
  final String? speaker;
  final String text;
  final String? sprite;
  final String? background;
  final String? next;

  const DialogueNode({
    required super.id,
    required this.text,
    this.speaker,
    this.sprite,
    this.background,
    this.next,
  });

  factory DialogueNode.fromJson(Map<String, dynamic> json) => DialogueNode(
        id: json['id'] as String,
        text: json['text'] as String,
        speaker: json['speaker'] as String?,
        sprite: json['sprite'] as String?,
        background: json['background'] as String?,
        next: json['next'] as String?,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'dialogue',
        'id': id,
        'text': text,
        if (speaker != null) 'speaker': speaker,
        if (sprite != null) 'sprite': sprite,
        if (background != null) 'background': background,
        if (next != null) 'next': next,
      };
}

/// A single option in a [ChoiceNode], leading to the node with id [next].
class SceneChoice {
  final String text;
  final String next;

  const SceneChoice({required this.text, required this.next});

  factory SceneChoice.fromJson(Map<String, dynamic> json) => SceneChoice(
        text: json['text'] as String,
        next: json['next'] as String,
      );

  Map<String, dynamic> toJson() => {'text': text, 'next': next};
}

/// A branching point offering the player one or more [SceneChoice]s.
class ChoiceNode extends SceneNode {
  final String? prompt;
  final List<SceneChoice> choices;

  const ChoiceNode({
    required super.id,
    required this.choices,
    this.prompt,
  });

  factory ChoiceNode.fromJson(Map<String, dynamic> json) => ChoiceNode(
        id: json['id'] as String,
        prompt: json['prompt'] as String?,
        choices: (json['choices'] as List)
            .map((c) => SceneChoice.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'choice',
        'id': id,
        if (prompt != null) 'prompt': prompt,
        'choices': choices.map((c) => c.toJson()).toList(),
      };
}

/// A node that hands off to a battle. [battleId] is an opaque identifier
/// the host app resolves to an actual `Battle` setup (team rosters,
/// Loadouts, etc.) - the story module itself never constructs a `Battle`.
/// After the battle resolves, the caller reports the outcome via
/// `StoryEngine.resolveBattle`, which routes to [onTeamAWinsNext]/
/// [onTeamBWinsNext]/[onDrawNext] as appropriate (null ends the scene).
class BattleTriggerNode extends SceneNode {
  final String battleId;
  final String? onTeamAWinsNext;
  final String? onTeamBWinsNext;
  final String? onDrawNext;

  const BattleTriggerNode({
    required super.id,
    required this.battleId,
    this.onTeamAWinsNext,
    this.onTeamBWinsNext,
    this.onDrawNext,
  });

  factory BattleTriggerNode.fromJson(Map<String, dynamic> json) =>
      BattleTriggerNode(
        id: json['id'] as String,
        battleId: json['battleId'] as String,
        onTeamAWinsNext: json['onTeamAWinsNext'] as String?,
        onTeamBWinsNext: json['onTeamBWinsNext'] as String?,
        onDrawNext: json['onDrawNext'] as String?,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'battleTrigger',
        'id': id,
        'battleId': battleId,
        if (onTeamAWinsNext != null) 'onTeamAWinsNext': onTeamAWinsNext,
        if (onTeamBWinsNext != null) 'onTeamBWinsNext': onTeamBWinsNext,
        if (onDrawNext != null) 'onDrawNext': onDrawNext,
      };
}

/// Marks the definite end of a scene (as opposed to a [DialogueNode] with
/// a null [DialogueNode.next], which ends implicitly).
class EndNode extends SceneNode {
  const EndNode({required super.id});

  factory EndNode.fromJson(Map<String, dynamic> json) =>
      EndNode(id: json['id'] as String);

  @override
  Map<String, dynamic> toJson() => {'type': 'end', 'id': id};
}
