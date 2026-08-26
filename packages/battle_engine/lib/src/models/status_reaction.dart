import 'damage_type.dart';

/// One entry in item 3b's reaction table: what happens when a character who
/// already carries a status is hit by a particular damage type, or has a
/// particular status land on them.
///
/// The point of the item is that 62 status effects existed and none of them
/// talked to each other. A status was a modifier you applied and forgot.
/// Reactions turn the catalogue into a web, where applying one thing sets up
/// another, and they do it from a small table rather than from more content:
/// twelve rows produce far more play than twelve more abilities would.
///
/// The shape is deliberately the same "bag of declarative options" the rest of
/// the engine uses. A reaction is data hanging off the status that reacts, and
/// exactly two places in the engine read it: the damage path, and the status
/// application path. No switch statement anywhere names a status by id.
///
/// A reaction is **never contested** (decision #G). It fires automatically
/// when its condition is met. A two-step play that had to win an infliction
/// roll at each step would come off about a fifth of the time, and nobody
/// builds around that.
class StatusReaction {
  /// Taking damage of this type fires the reaction. Null for a reaction that
  /// fires on a status landing instead.
  final DamageType? onDamageType;

  /// This status landing on the same character fires the reaction. Null for a
  /// damage-type reaction.
  ///
  /// No row in the shipped table uses this axis yet: all twelve fire on a
  /// damage type. It is here because the table grows in wave 3, when the new
  /// abilities land, and because the engine evaluates both axes for the same
  /// two lines of code.
  final String? onStatusApplied;

  /// The status the holder gains when the reaction fires. Null for a reaction
  /// whose whole effect is on the triggering hit (the Frozen shatter) or that
  /// only clears something.
  ///
  /// Naming the status that is already there is how a row stacks it: Scorched
  /// hit by Fire becomes Scorched again, which lands as a stack once item 5b
  /// gives it a stacking flag, and as a refresh until then.
  final String? becomes;

  /// Whether the status carrying this reaction is spent by it. True for a
  /// transformation (Wet becomes Frozen, and the Wet is gone), false for a
  /// row that builds on what is there (Scorched stacking, Corroded taking
  /// another coat of Acid).
  final bool consumesTrigger;

  /// A second status removed when the reaction fires, for a row that clears
  /// something other than its own trigger. Null for most rows.
  final String? alsoRemoves;

  /// Multiplier applied to the damage of the hit that fired the reaction.
  /// 1.0 leaves the hit alone; 2.0 is the Frozen shatter; 0 would make the
  /// hit deal nothing.
  final double damageMultiplier;

  /// Spreads [becomes] to one other character standing on the same line as
  /// the holder, on the holder's own side. Electrocuted arcing off a Thunder
  /// hit is the one row that uses it.
  final bool arcsToSameLine;

  const StatusReaction({
    this.onDamageType,
    this.onStatusApplied,
    this.becomes,
    this.consumesTrigger = false,
    this.alsoRemoves,
    this.damageMultiplier = 1.0,
    this.arcsToSameLine = false,
  }) : assert(
          onDamageType != null || onStatusApplied != null,
          'a reaction needs something to react to',
        );

  /// Whether [damageType] fires this reaction.
  bool firesOnDamage(DamageType damageType) => onDamageType == damageType;

  /// Whether [statusEffectId] landing fires this reaction.
  bool firesOnStatus(String statusEffectId) =>
      onStatusApplied == statusEffectId;
}
