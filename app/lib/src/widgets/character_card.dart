import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../data/describe.dart';

class TypeTag extends StatelessWidget {
  final String label;
  const TypeTag({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white54, fontSize: 9),
      ),
    );
  }
}

/// The rich AI profile card: name, skill class tag, description.
class ProfileCard extends StatelessWidget {
  final AiProfile profile;
  const ProfileCard({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                profile.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 6),
            TypeTag(label: skillClassLabel[profile.skillClass]!),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          profile.description,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }
}
