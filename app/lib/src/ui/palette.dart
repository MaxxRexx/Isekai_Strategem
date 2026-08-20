import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';

/// The app-wide palette: the "Rift Cyan" direction approved from the
/// style-mockup round, mirroring the HTML demo's colors.
abstract final class Palette {
  static const accent = Color(0xFF34D1C8);
  static const background = Color(0xFF0B0F14);
  static const panel = Color(0xFF121822);
  static const teamA = Color(0xFF34D1C8);
  static const teamB = Color(0xFFFF8A52);
  static const warn = Color(0xFFFFAB4D);
  static const danger = Color(0xFFFF5468);
  static const good = Color(0xFF57D98A);
  static const gold = Color(0xFFF0B429);
  /// A bent shot, and the Trion Backlash it costs. Violet because it is the
  /// one hue the battle log has not already given a meaning: amber is the
  /// Full Arms Trigger, gold is critical hits and stat values, red is death,
  /// cyan is status effects and your own squad, green is healing.
  static const bend = Color(0xFFA78BFA);

  static const hairline = Color(0x1AE9EBF1);

  /// Per-type portrait gradient pairs (top-left, bottom-right), matching
  /// the approved battle-screen mockup's tile colors.
  static const Map<CharacterType, (Color, Color)> tileGradient = {
    CharacterType.attack: (Color(0xFF7A2F2F), Color(0xFF3D1414)),
    CharacterType.defense: (Color(0xFF1F5A63), Color(0xFF0C2A2F)),
    CharacterType.support: (Color(0xFF8A6A1C), Color(0xFF40300C)),
    CharacterType.unique: (Color(0xFF4A2F7A), Color(0xFF1E1233)),
  };
}
