import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

/// Icon vocabulary for game concepts, standing in for the HTML demo's
/// inline SVG set until real art lands.
abstract final class GameIcons {
  static const attack = Icons.gps_fixed;
  static const defense = Icons.shield_outlined;
  static const support = Icons.healing;
  static const unique = Icons.auto_awesome;
  static const melee = Icons.sports_martial_arts;
  static const ranged = Icons.my_location;
  static const burst = Icons.bolt;
  static const heal = Icons.favorite_outline;
  static const status = Icons.blur_on;
  static const passive = Icons.brightness_low;
  static const blackTrigger = Icons.token_outlined;
  static const book = Icons.menu_book_outlined;

  static IconData forCharacterType(CharacterType type) => switch (type) {
    CharacterType.attack => attack,
    CharacterType.defense => defense,
    CharacterType.support => support,
    CharacterType.unique => unique,
  };

  static IconData forTrigger(Trigger t) => switch (t) {
    PassiveTrigger() => passive,
    ActiveTrigger a when a.attackSubtype == AttackSubtype.burst => burst,
    ActiveTrigger a when a.rangeTag.isAtRange => ranged,
    ActiveTrigger a when a.healAmount != null => heal,
    ActiveTrigger a
        when a.damageType == null && a.inflictedStatusEffects.isNotEmpty =>
      status,
    ActiveTrigger() => melee,
  };
}
