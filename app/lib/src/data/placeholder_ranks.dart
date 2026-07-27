import '../ui/rank.dart';

/// Stand-in per-character ranks, shown on portrait tiles until the real
/// account-wide mission/objective system (e.g. "win 5 in a row without a
/// Black Trigger") exists to actually earn them. Values for the 10
/// characters visible in the approved reference mockup are matched to it;
/// the rest are reasonable placeholders.
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
