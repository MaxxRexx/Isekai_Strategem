import 'ai_skill_class.dart';

/// Core targeting rule an [AiProfile] follows when it isn't misplaying
/// (see `AiSkillClassConfig.mistakeChance`).
enum AiTargetPriority {
  /// Focus-fire whoever has the least current health.
  lowestHealth,

  /// Like [lowestHealth] but also weighs Defense/resistances (only
  /// meaningful once `AiSkillClassConfig.matchupAwareEvaluation` is on).
  matchupAware,

  /// Target whoever has personally dealt the most cumulative damage this
  /// battle (`CharacterBattleState.cumulativeDamageDealt`) - "biggest
  /// realized threat", not a static stat proxy (The Grudge Holder).
  highestThreat,

  /// No real priority - whichever legal target comes first.
  firstAvailable,

  /// Uniform random among legal targets.
  random,
}

/// Core ability-choice rule an [AiProfile] follows when it isn't
/// misplaying.
enum AiAbilityPriority {
  /// Highest expected damage among usable abilities (mirrors
  /// `RuleBasedAi`'s original heuristic).
  highestDamage,

  /// Prefer an ability that inflicts a status effect over a pure damage
  /// one, even if the damage option scores higher.
  debuffFocused,

  /// Prefer an AOE-subtype ability whenever one is usable.
  aoeFavoring,

  /// Prefer the character's own Black Trigger active ability whenever
  /// it's usable, regardless of fit.
  blackTriggerFavoring,

  /// Prefer a support/heal ability (ally or self-targeted, non-damaging)
  /// over an attack, even when attacking would be better.
  supportFirst,

  /// Whichever ability is first in the equipped list, no evaluation at
  /// all (Button Masher).
  fixedOrder,

  /// Re-evaluates every turn: AOE if 2+ legal enemies are alive, debuff
  /// if some legal enemy has no active status effect, otherwise falls
  /// back to highest damage (The Prodigy).
  adaptive,
}

/// How aggressively an [AiProfile] leverages Full Arms Trigger's extra
/// actions once it triggers.
enum AiFatPolicy {
  /// Keep chaining whenever another ability is legally usable.
  alwaysChain,

  /// Only chain an extra action if it can secure a kill this turn, or if
  /// the team is clearly ahead on aggregate health (a tempo swing worth
  /// pressing); otherwise stop even though more actions are legal.
  killOrTempoOnly,

  /// Never voluntarily uses more than one ability a turn, even when FAT
  /// allows more.
  neverVoluntary,
}

/// One of the 20 individually-authored AI opponents: a strategic
/// identity ([targetPriority]/[abilityPriority]/[fatPolicy]/
/// [blackTriggerBias]/[preferredTriggerTags] for Loadout-building) at a
/// given [skillClass] (how well it's executed - see `AiSkillClassConfig`).
///
/// Each of the 5 skill classes has its own distinct 4 types (20 total,
/// not a shared 4-type grid) - the Intermediate 4 were specified
/// directly; the other 16 are drafted analogues at their own skill tier.
class AiProfile {
  final String id;
  final String name;
  final String description;
  final AiSkillClass skillClass;
  final AiTargetPriority targetPriority;
  final AiAbilityPriority abilityPriority;
  final AiFatPolicy fatPolicy;

  /// How strongly Loadout-building favors equipping a Black Trigger
  /// regardless of resonance fit. 0 = doesn't bother, 1 = always takes
  /// one even if it resonates poorly (The Gambler).
  final double blackTriggerBias;

  /// Trigger category/flavor tags this profile's Loadout-building
  /// favors (matched against `TriggerCategory`/AOE-subtype/status-
  /// inflicting/heal-granting, see `LoadoutBuilder`). Also biases
  /// in-battle ability scoring (see `ProfileDrivenAi._abilityPower`), so
  /// a profile stating a tag preference gets that preference reflected
  /// in actual play, not just at draft time.
  final Set<String> preferredTriggerTags;

  /// If true, once this character has landed a damaging hit on a target
  /// this battle, it keeps targeting that same target (while legal and
  /// alive) ahead of its normal `targetPriority` - tunnel vision on
  /// whoever it's already hurting (The Berserker).
  final bool fixatesOnLastDamagedTarget;

  /// If true, ability choice first looks at what `TriggerCategory` the
  /// opponent team most recently used and prefers a usable ability of
  /// that same category before falling back to `abilityPriority` -
  /// copying the opponent's last move rather than reading the board
  /// independently (The Copycat).
  final bool mirrorsOpponentLastCategory;

  /// If true, `AiAbilityPriority.aoeFavoring` only actually prefers an
  /// AOE option when at least two legal enemy targets are predicted to
  /// be within its kill range - AOE used with real judgment about when
  /// it's worth it, rather than on sight (The Sweeper).
  final bool aoeOnlyWhenMultipleInKillRange;

  /// If true, `AiAbilityPriority.supportFirst` skips the "would this
  /// support action actually help anyone" gate and prefers support
  /// whenever one is usable, regardless of need - leaning on buffs/heals
  /// to a fault rather than only when useful (The Turtle).
  final bool ignoresSupportUsefulnessGate;

  const AiProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.skillClass,
    required this.targetPriority,
    required this.abilityPriority,
    required this.fatPolicy,
    this.blackTriggerBias = 0.3,
    this.preferredTriggerTags = const {},
    this.fixatesOnLastDamagedTarget = false,
    this.mirrorsOpponentLastCategory = false,
    this.aoeOnlyWhenMultipleInKillRange = false,
    this.ignoresSupportUsefulnessGate = false,
  });

  AiSkillClassConfig get skillConfig =>
      AiSkillClassConfig.defaults[skillClass]!;

  // --- Beginner ---
  static const buttonMasher = AiProfile(
    id: 'button_masher',
    name: 'Button Masher',
    description: 'Targets whoever is first in its own target list and uses '
        'whatever ability is off cooldown in slot order.',
    skillClass: AiSkillClass.beginner,
    targetPriority: AiTargetPriority.firstAvailable,
    abilityPriority: AiAbilityPriority.fixedOrder,
    fatPolicy: AiFatPolicy.alwaysChain,
  );

  static const theTurtle = AiProfile(
    id: 'the_turtle',
    name: 'The Turtle',
    description: 'Leans on self-buffs and passives over attacking, to a '
        'fault, and never voluntarily chains FAT.',
    skillClass: AiSkillClass.beginner,
    targetPriority: AiTargetPriority.lowestHealth,
    abilityPriority: AiAbilityPriority.supportFirst,
    fatPolicy: AiFatPolicy.neverVoluntary,
    preferredTriggerTags: {'buff', 'defense'},
    ignoresSupportUsefulnessGate: true,
  );

  static const theCopycat = AiProfile(
    id: 'the_copycat',
    name: 'The Copycat',
    description: 'No real target discipline - picks whatever is in front '
        "of it rather than reading the board, and just mirrors whatever "
        "category of move the opponent used last.",
    skillClass: AiSkillClass.beginner,
    targetPriority: AiTargetPriority.random,
    abilityPriority: AiAbilityPriority.highestDamage,
    fatPolicy: AiFatPolicy.alwaysChain,
    mirrorsOpponentLastCategory: true,
  );

  static const theBerserker = AiProfile(
    id: 'the_berserker',
    name: 'The Berserker',
    description: 'Tunnel-visions on raw damage output with no target or '
        'resource discipline at all, fixating on whoever it last drew '
        'blood from.',
    skillClass: AiSkillClass.beginner,
    targetPriority: AiTargetPriority.firstAvailable,
    abilityPriority: AiAbilityPriority.highestDamage,
    fatPolicy: AiFatPolicy.alwaysChain,
    fixatesOnLastDamagedTarget: true,
  );

  // --- Amateur ---
  static const theSharpshooter = AiProfile(
    id: 'the_sharpshooter',
    name: 'The Sharpshooter',
    description: 'Overvalues Ranged/Burst options even when a weaker '
        'choice this turn.',
    skillClass: AiSkillClass.amateur,
    targetPriority: AiTargetPriority.lowestHealth,
    abilityPriority: AiAbilityPriority.highestDamage,
    fatPolicy: AiFatPolicy.alwaysChain,
    preferredTriggerTags: {'ranged', 'burst'},
  );

  static const theHealersCrutch = AiProfile(
    id: 'the_healers_crutch',
    name: "The Healer's Crutch",
    description: 'Over-prioritizes healing/support even when finishing a '
        'kill would end the fight faster.',
    skillClass: AiSkillClass.amateur,
    targetPriority: AiTargetPriority.lowestHealth,
    abilityPriority: AiAbilityPriority.supportFirst,
    fatPolicy: AiFatPolicy.alwaysChain,
    preferredTriggerTags: {'heal', 'buff'},
  );

  static const theMomentumChaser = AiProfile(
    id: 'the_momentum_chaser',
    name: 'The Momentum Chaser',
    description: 'Chains every FAT proc on principle, productive or not.',
    skillClass: AiSkillClass.amateur,
    targetPriority: AiTargetPriority.lowestHealth,
    abilityPriority: AiAbilityPriority.highestDamage,
    fatPolicy: AiFatPolicy.alwaysChain,
  );

  static const theGrudgeHolder = AiProfile(
    id: 'the_grudge_holder',
    name: 'The Grudge Holder',
    description: 'Fixates on whichever enemy looks like the biggest '
        'threat, ignoring current health or kill priority.',
    skillClass: AiSkillClass.amateur,
    targetPriority: AiTargetPriority.highestThreat,
    abilityPriority: AiAbilityPriority.highestDamage,
    fatPolicy: AiFatPolicy.alwaysChain,
  );

  // --- Intermediate (given directly) ---
  static const theExecutioner = AiProfile(
    id: 'the_executioner',
    name: 'The Executioner',
    description: 'Every character piles onto the same enemy until it dies, '
        'then the whole team retargets together.',
    skillClass: AiSkillClass.intermediate,
    targetPriority: AiTargetPriority.lowestHealth,
    abilityPriority: AiAbilityPriority.highestDamage,
    fatPolicy: AiFatPolicy.alwaysChain,
  );

  static const theAfflictor = AiProfile(
    id: 'the_afflictor',
    name: 'The Afflictor',
    description: 'Prioritizes landing status effects over raw damage, even '
        'when a straight attack would do more immediate damage.',
    skillClass: AiSkillClass.intermediate,
    targetPriority: AiTargetPriority.lowestHealth,
    abilityPriority: AiAbilityPriority.debuffFocused,
    fatPolicy: AiFatPolicy.alwaysChain,
    preferredTriggerTags: {'debuff'},
  );

  static const theBlastRadius = AiProfile(
    id: 'the_blast_radius',
    name: 'The Blast Radius',
    description: 'Reaches for AOE whenever one is off cooldown, even '
        'against a single remaining target.',
    skillClass: AiSkillClass.intermediate,
    targetPriority: AiTargetPriority.lowestHealth,
    abilityPriority: AiAbilityPriority.aoeFavoring,
    fatPolicy: AiFatPolicy.alwaysChain,
    preferredTriggerTags: {'aoe'},
  );

  static const theGambler = AiProfile(
    id: 'the_gambler',
    name: 'The Gambler',
    description: 'Always fires its Black Trigger the moment it can, '
        'regardless of resonance fit.',
    skillClass: AiSkillClass.intermediate,
    targetPriority: AiTargetPriority.lowestHealth,
    abilityPriority: AiAbilityPriority.blackTriggerFavoring,
    fatPolicy: AiFatPolicy.alwaysChain,
    blackTriggerBias: 1.0,
  );

  // --- Professional ---
  static const theTactician = AiProfile(
    id: 'the_tactician',
    name: 'The Tactician',
    description: "Executioner's discipline plus real judgment: weighs "
        'Defense/resistances, not just health.',
    skillClass: AiSkillClass.professional,
    targetPriority: AiTargetPriority.matchupAware,
    abilityPriority: AiAbilityPriority.highestDamage,
    fatPolicy: AiFatPolicy.killOrTempoOnly,
  );

  static const theController = AiProfile(
    id: 'the_controller',
    name: 'The Controller',
    description: 'Sequences a debuff before committing to a burst, so the '
        'setup actually buys something.',
    skillClass: AiSkillClass.professional,
    targetPriority: AiTargetPriority.matchupAware,
    abilityPriority: AiAbilityPriority.debuffFocused,
    fatPolicy: AiFatPolicy.killOrTempoOnly,
    preferredTriggerTags: {'debuff'},
  );

  static const theSweeper = AiProfile(
    id: 'the_sweeper',
    name: 'The Sweeper',
    description: 'Defaults to focus fire, but switches to AOE the moment '
        'two or more enemies are in kill range together.',
    skillClass: AiSkillClass.professional,
    targetPriority: AiTargetPriority.matchupAware,
    abilityPriority: AiAbilityPriority.aoeFavoring,
    fatPolicy: AiFatPolicy.killOrTempoOnly,
    preferredTriggerTags: {'aoe'},
    aoeOnlyWhenMultipleInKillRange: true,
  );

  static const theEconomist = AiProfile(
    id: 'the_economist',
    name: 'The Economist',
    description: 'Only spends extra FAT actions when they secure a kill or '
        'a clear tempo swing; otherwise banks resources.',
    skillClass: AiSkillClass.professional,
    targetPriority: AiTargetPriority.matchupAware,
    abilityPriority: AiAbilityPriority.highestDamage,
    fatPolicy: AiFatPolicy.killOrTempoOnly,
  );

  // --- Expert ---
  static const theGrandmaster = AiProfile(
    id: 'the_grandmaster',
    name: 'The Grandmaster',
    description: 'Full lookahead: predicts next-turn lethal thresholds and '
        'a fully optimized Loadout.',
    skillClass: AiSkillClass.expert,
    targetPriority: AiTargetPriority.matchupAware,
    abilityPriority: AiAbilityPriority.highestDamage,
    fatPolicy: AiFatPolicy.killOrTempoOnly,
  );

  static const theSilentBlade = AiProfile(
    id: 'the_silent_blade',
    name: 'The Silent Blade',
    description: 'Opens with debuff setup, then unloads a maximized burst '
        'with near-perfect FAT timing.',
    skillClass: AiSkillClass.expert,
    targetPriority: AiTargetPriority.matchupAware,
    abilityPriority: AiAbilityPriority.debuffFocused,
    fatPolicy: AiFatPolicy.killOrTempoOnly,
    preferredTriggerTags: {'debuff', 'aoe'},
  );

  static const theWall = AiProfile(
    id: 'the_wall',
    name: 'The Wall',
    description: 'Leans on World abilities and stacked passives to grind '
        "the opponent's resources down, then turns aggressive.",
    skillClass: AiSkillClass.expert,
    targetPriority: AiTargetPriority.matchupAware,
    abilityPriority: AiAbilityPriority.supportFirst,
    fatPolicy: AiFatPolicy.killOrTempoOnly,
    preferredTriggerTags: {'defense', 'buff'},
  );

  static const theProdigy = AiProfile(
    id: 'the_prodigy',
    name: 'The Prodigy',
    description: "Reads the board state each turn and switches between "
        'focus-fire, AOE, and debuff setup - the closest thing to playing '
        'a skilled human.',
    skillClass: AiSkillClass.expert,
    targetPriority: AiTargetPriority.matchupAware,
    abilityPriority: AiAbilityPriority.adaptive,
    fatPolicy: AiFatPolicy.killOrTempoOnly,
    preferredTriggerTags: {'aoe', 'debuff'},
  );

  static const List<AiProfile> all = [
    buttonMasher,
    theTurtle,
    theCopycat,
    theBerserker,
    theSharpshooter,
    theHealersCrutch,
    theMomentumChaser,
    theGrudgeHolder,
    theExecutioner,
    theAfflictor,
    theBlastRadius,
    theGambler,
    theTactician,
    theController,
    theSweeper,
    theEconomist,
    theGrandmaster,
    theSilentBlade,
    theWall,
    theProdigy,
  ];
}
