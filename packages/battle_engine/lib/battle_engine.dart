/// Pure-Dart tactical combat engine: data models + rules engine, no UI.
library battle_engine;

// AI
export 'src/ai/ai_profile.dart';
export 'src/ai/ai_skill_class.dart';
export 'src/ai/loadout_builder.dart';
export 'src/ai/profile_driven_ai.dart';
export 'src/ai/rule_based_ai.dart';

// Content
export 'src/content/black_trigger_catalog.dart';
export 'src/content/character_roster.dart';
export 'src/content/combo_catalog.dart';
export 'src/content/trigger_catalog.dart';

// Models
export 'src/models/battle_position.dart';
export 'src/models/black_trigger.dart';
export 'src/models/character.dart';
export 'src/models/character_perk.dart';
export 'src/models/combo.dart';
export 'src/models/character_type.dart';
export 'src/models/damage_type.dart';
export 'src/models/loadout.dart';
export 'src/models/passive_counter.dart';
export 'src/models/passive_effect.dart';
export 'src/models/reactive_effect.dart';
export 'src/models/resonance.dart';
export 'src/models/stats.dart';
export 'src/models/status_effect.dart';
export 'src/models/status_effect_catalog.dart';
export 'src/models/team.dart';
export 'src/models/teg_profile.dart';
export 'src/models/trigger.dart';
export 'src/models/trion.dart';
export 'src/models/unique_behavior.dart';
export 'src/models/world_ability_effect.dart';

// Config
export 'src/constants.dart';

// Util
export 'src/util/dice.dart';

// Story
export 'src/story/scene.dart';
export 'src/story/scene_node.dart';
export 'src/story/story_engine.dart';

// Engine
export 'src/engine/battle.dart';
export 'src/engine/character_battle_state.dart';
export 'src/engine/combat_engine.dart';
export 'src/engine/combo_recognizer.dart';
export 'src/engine/fat_engine.dart';
export 'src/engine/status_effect_engine.dart';
export 'src/engine/team_spirit_curve.dart';
export 'src/engine/trion_gain_engine.dart';
export 'src/engine/turn_engine.dart';
