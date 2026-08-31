// Dumps the roster and Trigger catalogs as JSON, which is what the game
// design document's appendices are kept in step with.
//
//   dart run tool/doc_facts.dart
//
// Appendix A (every Trigger) and Appendix B (the roster table) in
// docs/game_design.md carry hand-written prose around machine-checkable
// numbers. After a tuning pass, re-run this and update those numbers from it
// rather than transcribing them by hand, which is how they drift.
import 'dart:convert';

import 'package:battle_engine/battle_engine.dart';

Map<String, Object?> triggerFacts(ActiveTrigger t) => {
      'id': t.id,
      'name': t.name,
      'category': t.category.name,
      'trionCost': t.trionCost,
      'cooldownTurns': t.cooldownTurns,
      'equipCost': t.equipCost,
      'rangeTag': t.rangeTag.name,
      'abilityType': t.abilityType.name,
      'abilitySubtype': t.abilitySubtype.name,
      'targetCount': t.targetCount,
      'hitsPerUse': t.hitsPerUse,
      'targetAffiliation': t.targetAffiliation.name,
      'damageType': t.damageType?.name,
      'damage': t.damage?.toString(),
      'damageAverage': t.damage == null ? null : t.damage!.average.round(),
      'healAverage':
          t.healAmount == null ? null : t.healAmount!.average.round(),
      'statuses':
          t.inflictedStatusEffects.map((s) => s.statusEffectId).toList(),
      'uniqueBehavior': t.uniqueBehavior?.name,
    };

void main() {
  final catalog = TriggerCatalog.defaultCatalog;
  final out = {
    'roster': [
      for (final c in CharacterRoster.defaultRoster.all)
        {
          'id': c.id,
          'name': c.name,
          'type': c.type.name,
          'attack': c.baseStats.attack,
          'defense': c.baseStats.defense,
          'armor': c.baseStats.armor,
          'maxHealth': c.baseStats.maxHealth,
          'trionCapacity': c.baseStats.trionCapacity,
          'trionAffinity': c.baseStats.trionAffinity,
          'teamSpirit': c.baseStats.teamSpirit,
          'criticalChance': c.baseStats.criticalChance,
          'fatChance': c.baseStats.fatChance,
          'statusEffectInfliction': c.baseStats.statusEffectInfliction,
          'statusEffectResistance': c.baseStats.statusEffectResistance,
          'sideEffect': c.sideEffect?.name,
        }
    ],
    'triggers': [
      for (final t in catalog.activeTriggers) triggerFacts(t),
    ],
    'blackTriggers': [
      for (final bt in BlackTriggerCatalog.defaultCatalog.all)
        {
          'id': bt.id,
          'name': bt.name,
          'type': bt.type.name,
          'equipCost': bt.equipCost,
          'activeAbilities': [
            for (final a in bt.activeAbilities) triggerFacts(a),
          ],
        }
    ],
  };
  print(const JsonEncoder.withIndent('  ').convert(out));
}
