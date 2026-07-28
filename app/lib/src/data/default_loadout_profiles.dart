/// Which [AiProfile] (see `package:battle_engine`) seeds each character's
/// default Loadout via [LoadoutBuilder.build] - not a claim that "this AI
/// plays this character", just reusing its Loadout-building preferences
/// (preferred Trigger tags, Black Trigger bias) because they're the
/// closest fit to each character's own perk/flavor. This lets a player
/// draft a squad and hit Play without ever touching Triggers; every pick
/// stays fully editable afterward, including via the existing Auto-fill
/// (which re-rolls a random profile instead of this fixed one).
const defaultLoadoutProfileId = <String, String>{
  // "Last Ace" - banks everything on his Black Trigger, win or lose.
  'kaito_reyes': 'the_gambler',
  // "First Blood" - a decisive opening strike.
  'vela_ashworth': 'the_sharpshooter',
  // "Overwhelm" - AOE that punishes targets already carrying a debuff.
  'dross': 'the_prodigy',
  // "First Strike" - full intensity from turn one, never eases off.
  'ren_kobayashi': 'the_momentum_chaser',
  // "Feint" - baits the first hit, then punishes with a setup->burst.
  'airi_tanaka': 'the_silent_blade',
  // "Bulwark" - locks onto whatever threatens the team most and refuses
  // to let up until it's gone.
  'marren_osei': 'the_grudge_holder',
  // "Riposte" - a self-buffing counter-attacker.
  'ilona_vance': 'the_turtle',
  // "Absorb" - measured, shrugs off the first real hit and carries on.
  'bastian_cole': 'the_economist',
  // "Immovable" - always finds as many targets as intended.
  'dorian_voss': 'the_blast_radius',
  // "Guardian's Instinct" - decisive, protective judgment.
  'sable_whitlock': 'the_tactician',
  // "Combat Medic" - the roster's clearest dedicated healer.
  'priya_nakamura': 'the_healers_crutch',
  // "Weaken Resolve" - layers status effects onto the same target.
  'soren_talvik': 'the_afflictor',
  // "Devoted Aid" - so much recovery on tap that she just cycles through
  // her kit in order, no triage needed.
  'yuki_amaral': 'button_masher',
  // "Battery" - a resource/utility optimizer for the whole team.
  'haru_ellison': 'the_grandmaster',
  // "Warding Presence" - defensive buffs layered onto allies.
  'celestine_moreau': 'the_wall',
  // "Foresight" - reads the board and adapts rather than committing early.
  'zheng_anders': 'the_sweeper',
  // "Chain Reaction" - piles ability after ability onto the same target.
  'nadia_kessler': 'the_executioner',
  // "All or Nothing" - the classic berserker, most dangerous near zero.
  'rurik_voss': 'the_berserker',
  // "Decoy" - unpredictable; an attack against her can simply find nothing.
  'mireille_song': 'the_copycat',
  // "Versatile" - reads the matchup and sets up a debuff before
  // committing to a burst.
  'tobias_renner': 'the_controller',
};
