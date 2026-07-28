/// How skilled an [AiProfile] plays, independent of its strategic
/// identity (see `AiProfile`'s own target/ability/FAT choices). Beginner
/// through Expert.
enum AiSkillClass { beginner, amateur, intermediate, professional, expert }

/// Tunable knobs for one [AiSkillClass]: how often it misplays, and how
/// much it actually evaluates before acting.
class AiSkillClassConfig {
  /// Chance (0-1) that a given decision (target or ability choice) falls
  /// back to a simpler/random pick instead of the profile's intended
  /// strategy - this is what makes lower classes feel human and
  /// fallible rather than perfectly optimal.
  final double mistakeChance;

  /// Whether target selection considers more than raw health (Defense,
  /// resistances) - off for Beginner/Amateur (they only look at HP and
  /// damage numbers), on from Intermediate up.
  final bool matchupAwareEvaluation;

  /// Expert-only: predicts whether a target would survive this hit and
  /// prefers not to waste an attack that can't secure a kill this turn
  /// when a slightly different choice could.
  final bool usesLookahead;

  const AiSkillClassConfig({
    required this.mistakeChance,
    required this.matchupAwareEvaluation,
    this.usesLookahead = false,
  });

  static const Map<AiSkillClass, AiSkillClassConfig> defaults = {
    AiSkillClass.beginner: AiSkillClassConfig(
      mistakeChance: 0.40,
      matchupAwareEvaluation: false,
    ),
    AiSkillClass.amateur: AiSkillClassConfig(
      mistakeChance: 0.25,
      matchupAwareEvaluation: false,
    ),
    AiSkillClass.intermediate: AiSkillClassConfig(
      mistakeChance: 0.12,
      matchupAwareEvaluation: true,
    ),
    AiSkillClass.professional: AiSkillClassConfig(
      mistakeChance: 0.05,
      matchupAwareEvaluation: true,
    ),
    AiSkillClass.expert: AiSkillClassConfig(
      mistakeChance: 0.02,
      matchupAwareEvaluation: true,
      usesLookahead: true,
    ),
  };
}
