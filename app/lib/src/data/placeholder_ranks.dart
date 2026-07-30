import '../ui/rank.dart';

/// The player's own account-wide rank, earned through mission/objective
/// progress (not yet implemented). It's a single value for the whole
/// account, not per-character - every character in the player's own squad
/// shows this same rank, unlike [placeholderRanks] below (which is for
/// AI opponents/roster browsing, where a per-character value makes sense).
const playerAccountRank = CharacterRank.c;

/// The AI opponent's account-wide rank. Like the player's, it's a single
/// value for the whole opposing squad (every opponent character shows the
/// same badge) rather than the per-character [placeholderRanks]. Ranked
/// matchmaking pairs equal ranks, so this stands in as the player's own
/// rank until the real progression/matchmaking system exists.
const opponentAccountRank = playerAccountRank;

/// Stand-in per-character ranks for AI opponents (and roster browsing
/// before a squad is committed to), until the real system exists to
/// actually earn them. Values for the 10 characters visible in the
/// approved reference mockup are matched to it; the rest are reasonable
/// placeholders.
const placeholderRanks = <String, CharacterRank>{
  'ren_kobayashi': CharacterRank.a,
  'vela_ashworth': CharacterRank.c,
  'kaito_reyes': CharacterRank.s,
  'airi_tanaka': CharacterRank.b,
  'dross': CharacterRank.a,
  'ilona_vance': CharacterRank.b,
  'marren_osei': CharacterRank.a,
  'bastian_cole': CharacterRank.c,
  'dorian_voss': CharacterRank.b,
  'sable_whitlock': CharacterRank.s,
  'priya_nakamura': CharacterRank.b,
  'soren_talvik': CharacterRank.c,
  'yuki_amaral': CharacterRank.b,
  'haru_ellison': CharacterRank.a,
  'celestine_moreau': CharacterRank.b,
  'zheng_anders': CharacterRank.a,
  'nadia_kessler': CharacterRank.b,
  'rurik_voss': CharacterRank.c,
  'mireille_song': CharacterRank.b,
  'tobias_renner': CharacterRank.c,
};
