import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

import '../data/describe.dart';
import '../ui/palette.dart';

enum _AbilityKind { active, passive, world }

extension on _AbilityKind {
  String get label => switch (this) {
    _AbilityKind.active => 'ACTIVE',
    _AbilityKind.passive => 'PASSIVE',
    _AbilityKind.world => 'WORLD',
  };

  Color get color => switch (this) {
    _AbilityKind.active => Palette.accent,
    _AbilityKind.passive => Palette.gold,
    _AbilityKind.world => const Color(0xFFB18CFF),
  };
}

class _AbilityLine {
  final _AbilityKind kind;
  final String name;
  final String description;
  const _AbilityLine(this.kind, this.name, this.description);
}

/// A Black Trigger's description followed by each of its abilities, with a
/// highlighted ACTIVE/PASSIVE/WORLD tag in front of every one - a Black
/// Trigger can mix several actives and passives, or stand alone as a
/// single World ability, and it should be obvious at a glance which is
/// which instead of one undifferentiated block of text.
class BlackTriggerAbilityList extends StatelessWidget {
  final BlackTrigger blackTrigger;
  final TextStyle? style;

  const BlackTriggerAbilityList({
    super.key,
    required this.blackTrigger,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final bt = blackTrigger;
    final hasAbilities =
        bt.activeAbilities.isNotEmpty || bt.passiveAbilities.isNotEmpty;
    final baseStyle =
        style ?? const TextStyle(color: Colors.white70, fontSize: 11);

    final lines = hasAbilities
        ? [
            for (final a in bt.activeAbilities)
              _AbilityLine(
                _AbilityKind.active,
                a.name,
                describeActiveTrigger(a),
              ),
            for (final p in bt.passiveAbilities)
              _AbilityLine(
                _AbilityKind.passive,
                p.name,
                describePassiveEffect(p.effect),
              ),
          ]
        : bt.worldAbility != null
        ? [_AbilityLine(_AbilityKind.world, 'World Ability', bt.description)]
        : const <_AbilityLine>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A world-ability-only Black Trigger's description already IS the
        // ability's mechanical text (see the WORLD-tagged line below), so
        // it isn't repeated untagged up here too.
        if (hasAbilities && bt.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(bt.description, style: baseStyle),
          ),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 2,
              children: [
                _kindTag(line.kind),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${line.name}: ',
                        style: baseStyle.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      TextSpan(text: line.description, style: baseStyle),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _kindTag(_AbilityKind kind) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: kind.color.withValues(alpha: 0.16),
        border: Border.all(color: kind.color),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        kind.label,
        style: TextStyle(
          color: kind.color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
