/// Pure-Dart tactical combat engine: data models + rules engine, no UI.
library battle_engine;

// Models
export 'src/models/black_trigger.dart';
export 'src/models/character.dart';
export 'src/models/character_type.dart';
export 'src/models/damage_type.dart';
export 'src/models/loadout.dart';
export 'src/models/passive_effect.dart';
export 'src/models/resonance.dart';
export 'src/models/stats.dart';
export 'src/models/status_effect.dart';
export 'src/models/status_effect_catalog.dart';
export 'src/models/team.dart';
export 'src/models/trigger.dart';
export 'src/models/trion.dart';
export 'src/models/world_ability_effect.dart';

// Config
export 'src/constants.dart';

// Util
export 'src/util/dice.dart';

// Engine
export 'src/engine/character_battle_state.dart';
export 'src/engine/combat_engine.dart';
export 'src/engine/fat_engine.dart';
export 'src/engine/status_effect_engine.dart';
export 'src/engine/team_spirit_curve.dart';
export 'src/engine/trion_gain_engine.dart';
export 'src/engine/turn_engine.dart';
