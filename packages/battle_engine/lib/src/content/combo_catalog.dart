import '../engine/combo_recognizer.dart';
import '../models/combo.dart';
import '../models/trigger.dart';

/// Combat-v2 Phase I3: the Layer-1 (generic / emergent) combo catalog.
/// These apply to *any* squad - they key off structural facts (an ally's
/// setup status on the target, focus fire, an affliction to detonate)
/// rather than specific characters. Layer-2 signature combos (bespoke,
/// character/world-flavoured) are added later as their own entries.
///
/// Status groupings are intentionally coarse and tunable; they name the
/// existing status-effect catalog ids.
class ComboCatalog {
  ComboCatalog._();

  /// Hard/soft control: the target's ability to act or choose is denied.
  static const Set<String> controlStatuses = {
    'stunned',
    'silenced',
    'sealed',
    'prone',
    'petrified',
    'frozen',
    'choked',
    'forced_repetition',
    'forced_choice',
    'origin_lockout',
    'shadow_bound',
    'genjutsu_trapped',
    'charmed',
    'terrified',
    'suppressed',
    'isolation',
  };

  /// Vulnerability / stat-erosion debuffs: the target is weakened or exposed
  /// but not disabled - a setup worth exploiting.
  static const Set<String> vulnerabilityStatuses = {
    'exposed',
    'weakened',
    'marked',
    'shattered_guard',
    'slowed',
    'reeling',
    'sapped',
    'threatened',
    'hexed',
    'cursed',
    'blinded',
    'overwhelmed',
  };

  /// Afflictions (damage-over-time) worth "detonating" with a follow-up.
  static const Set<String> afflictionStatuses = {
    'poisoned',
    'bleeding',
    'corroded',
    'scorched',
    'electrocuted',
    'acid',
    'necrotic_wound',
    'sickened',
  };

  /// The Layer-1 generic combos, strongest first by [ComboDefinition.strength].
  static const List<ComboDefinition> generic = [
    ComboDefinition(
      id: 'control_then_strike',
      name: 'Control then Strike',
      flavor:
          'An ally locks the target down and a teammate capitalises before '
          'it can recover.',
      strength: 3,
      isSetupPayoff: true,
      condition: AllOf([
        PayoffIsOffensive(),
        AllyAppliedStatusToTarget(controlStatuses),
      ]),
    ),
    ComboDefinition(
      id: 'affliction_detonate',
      name: 'Affliction Detonate',
      flavor:
          'An energy follow-up ignites the affliction already eating away at '
          'the target.',
      strength: 2,
      condition: AllOf([
        PayoffIsOffensive(),
        PayoffOrigin(OriginTag.energy),
        TargetHasAnyStatus(afflictionStatuses),
      ]),
    ),
    ComboDefinition(
      id: 'setup_exploit',
      name: 'Setup Exploit',
      flavor:
          'A teammate pries the target open (exposed, weakened, marked) and '
          'the payoff drives through the gap.',
      strength: 2,
      isSetupPayoff: true,
      condition: AllOf([
        PayoffIsOffensive(),
        AllyAppliedStatusToTarget(vulnerabilityStatuses),
      ]),
    ),
    ComboDefinition(
      id: 'focus_fire',
      name: 'Focus Fire',
      flavor: 'A second attacker piles onto an enemy an ally already hit.',
      strength: 1,
      condition: AllOf([
        PayoffIsOffensive(),
        AllyStruckTarget(),
      ]),
    ),
  ];

  /// Layer 2: signature / authored combos (Phase I4). These name specific
  /// triggers (and can name characters/perks) for bespoke, higher-reward
  /// plays. Seeded here with thematic trigger chains; the full set is
  /// designer content added incrementally. Strengths run above the generic
  /// tier so a signature play amplifies harder (still capped at 20% by the
  /// consumer). Tunable (Phase H).
  static const List<ComboDefinition> signature = [
    ComboDefinition(
      id: 'frozen_detonation',
      name: 'Frozen Detonation',
      flavor:
          'A teammate flash-freezes the target with Frost Lance; the follow-up '
          'Cinderburst cracks the ice for a violent thermal shock.',
      strength: 4,
      isSetupPayoff: true,
      condition: AllOf([
        PayoffIsOffensive(),
        PayoffUsesTrigger({'cinderburst'}),
        AllyUsedTriggerOnTarget({'frost_lance'}),
      ]),
    ),
    ComboDefinition(
      id: 'terror_cascade',
      name: 'Terror Cascade',
      flavor:
          'Nightmare Pulse primes the mind; Dread Gaze lands while the target '
          'is already reeling in fear, compounding the dread.',
      strength: 4,
      isSetupPayoff: true,
      condition: AllOf([
        PayoffIsOffensive(),
        PayoffUsesTrigger({'dread_gaze'}),
        AllyUsedTriggerOnTarget({'nightmare_pulse'}),
      ]),
    ),
    ComboDefinition(
      id: 'shatterpoint_execution',
      name: 'Shatterpoint Execution',
      flavor:
          'Shatterpoint comes down on an enemy an ally has already softened - '
          'the finishing blow of a focused takedown.',
      strength: 5,
      condition: AllOf([
        PayoffIsOffensive(),
        PayoffUsesTrigger({'shatterpoint'}),
        AllyStruckTarget(),
      ]),
    ),
  ];

  /// The full recognizable catalog: generic (Layer 1) plus signature
  /// (Layer 2), strongest-first ordering handled by the recognizer.
  static const List<ComboDefinition> all = [...generic, ...signature];

  /// The default recognizer over the full catalog.
  static const ComboRecognizer defaultRecognizer = ComboRecognizer(all);
}
