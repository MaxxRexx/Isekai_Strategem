/// A character's identity **inside one battle**.
///
/// Outside a battle a character is identified by their roster id
/// (`ilona_vance`), and that is the right key: there is exactly one Ilona
/// Vance in the roster. Inside a battle it is not enough. Both squads may
/// field the same character, and nearly everything in a battle is keyed by
/// identity, so two Ilona Vances drafted onto opposite squads would share one
/// health pool, count each other as teammates, and die together. That is
/// exactly what the #2 playtest found, and the stopgap since then has been to
/// forbid it at the draft screens.
///
/// A **combatant id** is the squad's id and the character's id joined:
/// `player:ilona_vance` against `ai:ilona_vance`. Two things follow, and both
/// are the point:
///
///  - Two squads fielding the same character produce two different keys, so
///    they are two combatants with their own health, statuses and position.
///  - The same character twice **within one squad** produces the *same* key,
///    which is still a genuine mistake, so the battle's own duplicate guard
///    keeps catching it.
///
/// The squad's own id is the prefix rather than a separate side enum, so the
/// two can never disagree about which squad a combatant belongs to.
abstract final class CombatantIds {
  /// Separator between the squad id and the character id. A colon, because no
  /// roster id or team id contains one, and it reads as a namespace.
  static const String separator = ':';

  /// The combatant id for [characterId] fielded by the squad [teamId].
  static String of(String teamId, String characterId) =>
      '$teamId$separator$characterId';

  /// The roster id inside [combatantId].
  ///
  /// Deliberately tolerant of a plain character id: a battle built without
  /// combatant ids (an engine test, a tool harness) keys everything by the
  /// character's own id, and this has to answer for those too. So this is
  /// safe to call anywhere a battle id crosses back out to the roster,
  /// whichever kind of id it turns out to be holding.
  static String characterOf(String combatantId) {
    final at = combatantId.indexOf(separator);
    return at < 0 ? combatantId : combatantId.substring(at + 1);
  }

  /// The squad id inside [combatantId], or null for a plain character id.
  static String? teamOf(String combatantId) {
    final at = combatantId.indexOf(separator);
    return at < 0 ? null : combatantId.substring(0, at);
  }

  /// Whether [id] carries a squad prefix.
  static bool isScoped(String id) => id.contains(separator);
}
