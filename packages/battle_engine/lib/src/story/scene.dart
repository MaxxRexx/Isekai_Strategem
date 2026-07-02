import 'scene_node.dart';

/// A story scene: a graph of [SceneNode]s reachable by id, starting at
/// [startNodeId]. Deserializes directly from a scene script's JSON (e.g.
/// loaded from a story asset file); the host app owns loading the file
/// itself, this class only owns the shape.
class Scene {
  final String id;
  final String startNodeId;
  final Map<String, SceneNode> nodesById;

  const Scene({
    required this.id,
    required this.startNodeId,
    required this.nodesById,
  });

  SceneNode operator [](String nodeId) {
    final node = nodesById[nodeId];
    if (node == null) {
      throw ArgumentError('Scene "$id" has no node with id "$nodeId"');
    }
    return node;
  }

  SceneNode get startNode => this[startNodeId];

  factory Scene.fromJson(Map<String, dynamic> json) {
    final nodes = (json['nodes'] as List)
        .map((n) => SceneNode.fromJson(n as Map<String, dynamic>))
        .toList();
    return Scene(
      id: json['id'] as String,
      startNodeId: json['startNodeId'] as String,
      nodesById: {for (final n in nodes) n.id: n},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startNodeId': startNodeId,
        'nodes': nodesById.values.map((n) => n.toJson()).toList(),
      };
}
