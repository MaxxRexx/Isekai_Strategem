/// One-line flavor text per roster character, shown on character cards.
/// Purely descriptive; the engine never reads any of this.
const characterFlavor = <String, String>{
  'kaito_reyes':
      'A duelist who fights alone by choice, at his most dangerous with no one left to protect.',
  'vela_ashworth':
      'Strikes before her target even registers the fight has started.',
  'dross':
      'Reads the battlefield like a puzzle, and punishes anyone already bleeding.',
  'ren_kobayashi':
      'Opens every engagement at full intensity and never eases off.',
  'airi_tanaka':
      'Lets the first blow land wrong, then makes the enemy regret ever swinging.',
  'marren_osei':
      'A wall that gets harder to break the more his team needs him to hold.',
  'ilona_vance':
      'Turns every failed attack against her into the opening for her own.',
  'bastian_cole':
      'Shrugs off the first real hit of any fight like it never happened.',
  'dorian_voss':
      'Nothing narrows his aim. His shots always find as many targets as intended.',
  'sable_whitlock':
      'Steps between his allies and danger without waiting to be asked, once.',
  'priya_nakamura':
      'Finds the ally closest to falling and pours everything into keeping them up.',
  'soren_talvik':
      'Layers curse over curse until the target can barely remember what normal feels like.',
  'yuki_amaral':
      'Draws in every kind of healing like a plant turning toward the sun.',
  'haru_ellison':
      "Her presence alone keeps her team's resources flowing a little faster.",
  'celestine_moreau':
      "Wraps her allies' buffs in a ward that shrugs off whatever follows.",
  'zheng_anders':
      "Sees the roll before it lands, and gets to try again if it doesn't.",
  'nadia_kessler':
      'Chains one strike into the next, each one hitting harder than the last.',
  'rurik_voss': 'The closer he gets to zero, the more dangerous he becomes.',
  'mireille_song':
      'Sometimes an attack against her simply finds nothing there.',
  'tobias_renner': 'Adapts mid-fight, sharpening whatever he leaned on last.',
};

class StatusInfo {
  final int duration;
  final String effect;
  const StatusInfo(this.duration, this.effect);
}

/// Player-facing summaries per status effect display name, used for badge
/// tooltips and the How to Play list.
const statusInfo = <String, StatusInfo>{
  'Acid': StatusInfo(3, '-5 Armor'),
  'Wet': StatusInfo(3, 'Immune to Fire; vulnerable to Lightning and Cold'),
  'Stunned': StatusInfo(1, 'Prevents all actions; zeroes Team Spirit'),
  'Threatened': StatusInfo(2, 'Disadvantage on ranged attack rolls'),
  'Sickened': StatusInfo(3, 'Vulnerable to 4 random damage types'),
  'Sapped': StatusInfo(
    3,
    'Drains 25% of Trion Capacity to whoever inflicted it',
  ),
  'Reeling': StatusInfo(
    3,
    '-1 Attack per remaining turn (stronger early, fades out)',
  ),
  'Prone': StatusInfo(1, 'Locks a random equipped ability each turn'),
  'Prepared': StatusInfo(3, '+1 Attack per remaining turn (builds up)'),
  'Poisoned': StatusInfo(
    3,
    "Disadvantage on the poisoned character's own attack rolls",
  ),
  'Frozen': StatusInfo(1, 'Prevents all actions; zeroes Trion Affinity'),
  'Bleeding': StatusInfo(
    3,
    '8 damage at turn start (Slashing); disadvantage on their own status-resistance rolls',
  ),
  'Blinded': StatusInfo(
    2,
    'Ranged target count reduced by 1; disadvantage on ranged attack rolls',
  ),
  'Braced': StatusInfo(3, '+1 Defense per remaining turn'),
  'Charmed': StatusInfo(
    3,
    "Can't target the charmer; charmer has advantage on rolls against them",
  ),
  'Electrocuted': StatusInfo(2, '1d4 damage at turn start (Lightning)'),
  'Regenerating': StatusInfo(3, 'Heals 3 at turn start'),
  'Empowered': StatusInfo(2, '+25% outgoing damage'),
  'Weakened': StatusInfo(3, '-25% outgoing damage'),
  'Focused': StatusInfo(2, 'Advantage on attack rolls'),
  'Guarded': StatusInfo(2, 'Takes 25% less damage from everything'),
  'Exposed': StatusInfo(2, 'Takes 25% more damage from everything'),
  'Marked': StatusInfo(
    1,
    'Takes 50% more damage; marker has advantage on rolls against them',
  ),
  'Cursed': StatusInfo(3, 'Prevents all healing'),
  'Silenced': StatusInfo(1, 'Prevents all actions'),
  'Enraged': StatusInfo(2, '+50% outgoing damage, -3 Defense'),
  'Fatigued': StatusInfo(3, '-2 Attack, -2 Defense'),
  'Inspired': StatusInfo(2, '+2 Attack, +2 Defense'),
  'Shattered Guard': StatusInfo(2, 'Zeroes Armor'),
  'Overcharged': StatusInfo(2, 'Trion costs halved'),
  'Choked': StatusInfo(2, 'Trion costs doubled'),
  'Petrified': StatusInfo(
    2,
    'Prevents all actions; takes 50% less damage; zeroes Team Spirit',
  ),
  'Terrified': StatusInfo(
    2,
    "Disadvantage on attack/ranged-attack rolls; can't target the source",
  ),
  'Slowed': StatusInfo(
    2,
    '-1 Defense per remaining turn; disadvantage on attack rolls',
  ),
  'Hastened': StatusInfo(
    2,
    'Advantage on attack rolls; +1 Attack per remaining turn',
  ),
  'Scorched': StatusInfo(
    2,
    'Vulnerable to Fire; 12 damage at turn start (Fire)',
  ),
  'Chilled': StatusInfo(2, 'Vulnerable to Cold; -1 Attack per remaining turn'),
  'Corroded': StatusInfo(2, '-3 Armor; vulnerable to Acid'),
  'Shadow-Bound': StatusInfo(
    2,
    'Locks a random equipped ability each turn; disadvantage on attack rolls',
  ),
  'Genjutsu Trapped': StatusInfo(
    1,
    'Prevents all actions; drains 15% Trion Capacity to the causer',
  ),
  'Sealed': StatusInfo(2, 'Zeroes Trion Affinity and FAT Chance'),
  'Overwhelmed': StatusInfo(
    2,
    'Zeroes Critical Chance; disadvantage on attack rolls',
  ),
  'Adrenaline Rush': StatusInfo(2, '+15 Critical Chance'),
  'Battle Trance': StatusInfo(2, '+20 FAT Chance'),
  'Suppressed': StatusInfo(2, '-5 Status Effect Infliction'),
  'Warded': StatusInfo(2, '+10 Status Effect Resistance'),
  'Hexed': StatusInfo(2, '-10 Status Effect Resistance'),
  'Radiant Blessing': StatusInfo(
    3,
    'Heals 1 at turn start; +10 max health; takes 10% less damage',
  ),
  'Necrotic Wound': StatusInfo(
    3,
    '12 damage at turn start (Necrotic); prevents all healing',
  ),
};
