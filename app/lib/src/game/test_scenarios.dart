import 'package:battle_engine/battle_engine.dart';

import 'draft.dart';
import 'play_session.dart';

/// A pre-arranged battle that puts one specific rule in front of the player
/// in a turn or two.
///
/// Screening (item 1b) and Bail Out (item #2) are both merged and both carry
/// behaviour that has only ever been seen by a test. The cases that matter
/// are hard to reach from an ordinary battle: they need a particular board, a
/// particular pair of health values, and sometimes a body already lying on
/// the field before anybody has acted. Each scenario here sets that up in one
/// tap, says what to do, and says what should happen, so a case can be judged
/// in a minute instead of being fished for across a twenty-round match.
///
/// These are for a person to look at, not an assertion suite. The engine's own
/// tests already say the code does what the code says; what nobody has checked
/// is whether the *interface* tells the player any of it.
class TestScenario {
  final String id;
  final String name;

  /// The work item this exercises, shown as a chip on the picker.
  final String item;

  /// One line on what this scenario is for.
  final String goal;

  /// What the tester should do, in order.
  final List<String> steps;

  /// What should happen if the feature is right. Written so that a "no" is
  /// as easy to spot as a "yes".
  final List<String> expect;

  /// A known reason this scenario might not play out as written, or null.
  /// Honest about the dice: some of these need an attack to land.
  final String? caveat;

  final List<String> playerIds;
  final List<String> enemyIds;

  /// Trigger ids per character. Exactly four active abilities each, and the
  /// total equip cost has to fit the character's Trion Capacity, same as any
  /// Loadout the player could build by hand.
  final Map<String, List<String>> kits;

  /// Where each character starts, overriding the position their kit's range
  /// bands would otherwise derive.
  final Map<String, BattlePosition> positions;

  /// Starting health, for anyone who should not begin at full.
  final Map<String, int> health;

  /// Characters who begin the battle as a Bailing Out body. Used by the cases
  /// that need a body on the board before anybody has had a turn.
  final Set<String> bailingOut;

  /// Characters who are already gone, for the cases about a squad's last
  /// member.
  final Set<String> destroyed;

  /// Trion each squad starts with, so nothing under test is blocked by the
  /// economy. Item #4 owns the real numbers; these are deliberately generous.
  final int startingTrion;

  /// The AI driving the opposing squad. Held on the scenario rather than
  /// hardcoded in [start] because the battle screen shows the opponent's
  /// profile, so the two would otherwise be able to disagree.
  final String opponentProfileId;

  const TestScenario({
    required this.id,
    required this.name,
    required this.item,
    required this.goal,
    required this.steps,
    required this.expect,
    this.caveat,
    required this.playerIds,
    required this.enemyIds,
    required this.kits,
    this.positions = const {},
    this.health = const {},
    this.bailingOut = const {},
    this.destroyed = const {},
    this.startingTrion = 120,
    this.opponentProfileId = 'button_masher',
  });

  Loadout loadoutFor(String characterId) => Loadout(
        characterId: characterId,
        triggers: [
          for (final id in kits[characterId]!) triggerCatalog[id],
        ],
      );

  Map<String, Loadout> get playerLoadouts => {
        for (final id in playerIds) id: loadoutFor(id),
      };

  Map<String, Loadout> get enemyLoadouts => {
        for (final id in enemyIds) id: loadoutFor(id),
      };

  /// Builds the session this scenario describes. The player always moves
  /// first: a scenario the tester cannot act on immediately is a scenario
  /// they have to sit through.
  PlaySession start() => PlaySession.start(
        playerCharacterIds: playerIds,
        playerLoadouts: playerLoadouts,
        opponentCharacterIds: enemyIds,
        opponentProfileId: opponentProfileId,
        opponentLoadouts: enemyLoadouts,
        firstTurn: 'teamA',
        arrange: arrange,
      );

  /// Sets the board up on the built battle, immediately before the opening
  /// turn. Public so a test can arrange a battle without going through the
  /// interface.
  void arrange(Battle battle) {
    battle.teamA.trionPool.gain(startingTrion);
    battle.teamB.trionPool.gain(startingTrion);

    positions.forEach((id, position) {
      battle.states[id]!.position = position;
    });
    health.forEach((id, value) {
      battle.states[id]!.currentHealth = value;
    });

    // A body already on the board. Set directly rather than by dealing
    // damage, because `noteHealthChanged` is what turns a drop to zero into a
    // window and it has nothing to do here: a fresh state carries no reactive
    // effects for it to clear, and the window's own arming happens at the
    // turn boundary either way.
    for (final id in bailingOut) {
      final state = battle.states[id]!;
      state.currentHealth = 0;
      state.bailOutState = BailOutState.bailingOut;
    }

    for (final id in destroyed) {
      final state = battle.states[id]!;
      state.currentHealth = 0;
      state.bailOutState = BailOutState.destroyed;
    }
  }
}

// Four kits, each exactly four active abilities and comfortably inside the
// smallest Trion Capacity in the roster (100).
const _brawler = ['twin_fang_strike', 'shatterpoint', 'cleave', 'guardians_aegis'];
const _sniper = ['longshot', 'split_shot', 'frag_grenade', 'venom_needle'];
const _controller = [
  'charm_whisper',
  'twin_fang_strike',
  'guardians_aegis',
  'shatterpoint',
];
const _refuser = [
  'refuse_to_bail',
  'twin_fang_strike',
  'guardians_aegis',
  'shatterpoint',
];

/// The player squad used by most scenarios: the roster's hardest hitter at
/// the front, so a kill that a scenario depends on actually lands.
const _playerSquad = ['rurik_voss', 'kaito_reyes', 'mireille_song'];

/// The opposing squad, picked for low Defense for the same reason.
const _enemySquad = ['vela_ashworth', 'ren_kobayashi', 'nadia_kessler'];

const _front = BattlePosition.front;
const _middle = BattlePosition.middle;
const _back = BattlePosition.back;

final List<TestScenario> testScenarios = [
  TestScenario(
    id: 'read_the_board',
    name: 'Read the board',
    item: '1b',
    goal:
        'Nothing to kill. Just check that the battlefield strip says what the '
        'screening rule actually computes.',
    steps: [
      'Look at the battlefield strip without doing anything.',
      'Tap each of your three characters in turn and read the distance to '
          'each enemy line.',
    ],
    expect: [
      'Your squad stands Front, Middle, Back. The enemy has two on their '
          'Front line and one on their Back, so their Middle line is empty.',
      'The empty enemy Middle line reads as a dash, not as a distance.',
      'The enemy Back line carries one screening pip, because two enemies '
          'stand on a line strictly in front of it.',
      'From your Front character the enemy Front reads 0 and the enemy Back '
          'reads 3: your step 0, their step 2, plus one screen.',
      'From your Back character the same enemy Back line reads 5: your step '
          '2, their step 2, plus one screen.',
    ],
    playerIds: _playerSquad,
    enemyIds: _enemySquad,
    kits: {
      'rurik_voss': _brawler,
      'kaito_reyes': _brawler,
      'mireille_song': _sniper,
      'vela_ashworth': _brawler,
      'ren_kobayashi': _brawler,
      'nadia_kessler': _sniper,
    },
    positions: {
      'rurik_voss': _front,
      'kaito_reyes': _middle,
      'mireille_song': _back,
      'vela_ashworth': _front,
      'ren_kobayashi': _front,
      'nadia_kessler': _back,
    },
  ),

  TestScenario(
    id: 'screen_holds',
    name: 'The screen holds',
    item: '1b',
    goal:
        'Two enemies standing in front of a third should put that third out '
        'of Close Range reach entirely.',
    steps: [
      'Tap Rurik, at your Front line, and select Twin Fang Strike (Close '
          'Range).',
      'Try to aim it at Nadia Kessler on the enemy Back line.',
    ],
    expect: [
      'Nadia is not offered as a target.',
      'The strip shows her at distance 4: your step 0, her step 2, plus two '
          'screening enemies. Close Range reaches 0 to 2.',
      'The ability, or the strip, says why in plain words rather than just '
          'greying out. Screening should be named, and so should the fix.',
      'Vela on their Front line reads 0, and Ren on their Middle reads 2, '
          'both reachable. Only the far line is walled off.',
    ],
    playerIds: _playerSquad,
    enemyIds: _enemySquad,
    kits: {
      'rurik_voss': _brawler,
      'kaito_reyes': _brawler,
      'mireille_song': _sniper,
      'vela_ashworth': _brawler,
      'ren_kobayashi': _brawler,
      'nadia_kessler': _sniper,
    },
    positions: {
      'rurik_voss': _front,
      'kaito_reyes': _front,
      'mireille_song': _back,
      'vela_ashworth': _front,
      'ren_kobayashi': _middle,
      'nadia_kessler': _back,
    },
  ),

  TestScenario(
    id: 'body_screens',
    name: 'A body still screens',
    item: '1b and #2',
    goal:
        'Killing a screen does not open the lane. The body left behind goes '
        'on screening until it is cleared or recalled, which is the single '
        'place these two items meet.',
    steps: [
      'Note the distance from Rurik to either enemy on the Back line: it '
          'should read 3, with one screening pip.',
      'Turn 1: kill Vela at the enemy Front with Twin Fang Strike. She is on '
          '6 health.',
      'Look at the strip again before ending your turn.',
      'Turn 2: hit the body with any damaging ability to destroy it, then '
          'look at the strip once more.',
    ],
    expect: [
      'Vela drops and shows a colourless BAILING pill, not a defeated state.',
      'The distance to the Back line stays at 3 and the screening pip stays, '
          'because her body is still standing on the line in front.',
      'Once the body is destroyed the distance falls to 2 and the pip goes, '
          'and the Back line becomes reachable by Close Range.',
      'The battle log names the body being destroyed and says your squad '
          'banked the attacker\'s share of Trion for it.',
    ],
    caveat:
        'Twin Fang Strike still has to land. Rurik has Attack 14 against '
        'Vela\'s Defense 3, so it usually does, but a miss just means '
        'trying again next turn.',
    playerIds: _playerSquad,
    enemyIds: _enemySquad,
    kits: {
      'rurik_voss': _brawler,
      'kaito_reyes': _brawler,
      'mireille_song': _sniper,
      'vela_ashworth': _brawler,
      'ren_kobayashi': _brawler,
      'nadia_kessler': _sniper,
    },
    positions: {
      'rurik_voss': _front,
      'kaito_reyes': _front,
      'mireille_song': _back,
      'vela_ashworth': _front,
      'ren_kobayashi': _back,
      'nadia_kessler': _back,
    },
    health: {'vela_ashworth': 6},
  ),

  TestScenario(
    id: 'bending_shot',
    name: 'The bending shot',
    item: '1b',
    goal:
        'Breaking a screen in the same turn you shoot past it should never '
        'waste the shot. It bends to reach, and the squad pays next turn.',
    steps: [
      'Vela is already a Bailing Out body on the enemy Front line, screening '
          'Ren behind her.',
      'Tap Mireille at your Front line and queue Longshot (Long Range, '
          'reaches 2 to 4) at Ren. Ren is at distance 2 right now: your step '
          '0, his step 1, plus the body screening him.',
      'Without ending your turn, tap Rurik and queue Twin Fang Strike at the '
          'body. Queue order matters: the body has to be cleared before the '
          'shot resolves, so make sure Rurik\'s strike sits above the '
          'Longshot in the queue.',
      'End the turn and read the log.',
    ],
    expect: [
      'The body is destroyed first, which drops Ren to distance 1, under '
          'Longshot\'s minimum of 2.',
      'The Longshot still lands rather than fizzling.',
      'The log says the shot bent, in its own words, and says what it cost.',
      'Your squad\'s Trion income is capped next turn: Trion Backlash. '
          'Check the pool at the start of your next turn.',
    ],
    caveat:
        'If the queue resolves the Longshot before the strike, nothing bends '
        'and the shot simply lands normally. That is the ordinary case, not a '
        'bug: re-run and queue the strike first.',
    playerIds: _playerSquad,
    enemyIds: _enemySquad,
    kits: {
      'rurik_voss': _brawler,
      'kaito_reyes': _brawler,
      'mireille_song': _sniper,
      'vela_ashworth': _brawler,
      'ren_kobayashi': _brawler,
      'nadia_kessler': _sniper,
    },
    positions: {
      'rurik_voss': _front,
      'kaito_reyes': _front,
      'mireille_song': _front,
      'vela_ashworth': _front,
      'ren_kobayashi': _middle,
      'nadia_kessler': _back,
    },
    bailingOut: {'vela_ashworth'},
  ),

  TestScenario(
    id: 'window',
    name: 'The window: recall or destroy',
    item: '#2',
    goal:
        'The contested window itself. One setup, two endings, and the fork is '
        'the whole point of the item.',
    steps: [
      'Turn 1: kill Vela at the enemy Front. She is on 6 health.',
      'End your turn and let the enemy have theirs. The body should still be '
          'standing afterwards.',
      'Turn 2 is the window. Pick one: hit the body with any damaging '
          'ability, or leave it alone and end the turn.',
      'Run the scenario twice, once each way.',
    ],
    expect: [
      'Left alone, the body is recalled at the end of your turn 2 and the '
          'ENEMY squad banks the Trion Salvage, 20% of her base Capacity.',
      'Hit, the body is destroyed instead, the Salvage is denied, and YOUR '
          'squad banks the attacker\'s share, 10% of the same base.',
      'Either way she is gone for good. This is not a revive, and the log '
          'should not read like one.',
      'The two endings read differently in the log, and both name the Trion '
          'that moved and which squad got it.',
    ],
    caveat:
        'The window opens at the start of your turn 2, not straight after the '
        'kill, so the enemy turn in between is expected to pass with the body '
        'still there.',
    playerIds: _playerSquad,
    enemyIds: _enemySquad,
    kits: {
      'rurik_voss': _brawler,
      'kaito_reyes': _brawler,
      'mireille_song': _sniper,
      'vela_ashworth': _brawler,
      'ren_kobayashi': _brawler,
      'nadia_kessler': _sniper,
    },
    positions: {
      'rurik_voss': _front,
      'kaito_reyes': _front,
      'mireille_song': _middle,
      'vela_ashworth': _front,
      'ren_kobayashi': _middle,
      'nadia_kessler': _back,
    },
    health: {'vela_ashworth': 6},
  ),

  TestScenario(
    id: 'body_targeting',
    name: 'Only damage may be aimed at a body',
    item: '#2',
    goal:
        'A body can be destroyed but not debuffed, healed or charmed. Check '
        'the target picker agrees.',
    steps: [
      'Vela is already a body on the enemy Front line.',
      'Tap Kaito and select Charm Whisper, which deals no damage.',
      'Look at who it offers as targets.',
      'Now select Twin Fang Strike on the same character and compare.',
    ],
    expect: [
      'Charm Whisper does not offer the body. Ren and Nadia are still fair '
          'game if they are in band.',
      'Twin Fang Strike does offer the body.',
      'Nothing in the interface implies you could heal or buff the body '
          'either.',
    ],
    playerIds: _playerSquad,
    enemyIds: _enemySquad,
    kits: {
      'rurik_voss': _brawler,
      'kaito_reyes': _controller,
      'mireille_song': _sniper,
      'vela_ashworth': _brawler,
      'ren_kobayashi': _brawler,
      'nadia_kessler': _sniper,
    },
    positions: {
      'rurik_voss': _front,
      'kaito_reyes': _front,
      'mireille_song': _middle,
      'vela_ashworth': _front,
      'ren_kobayashi': _middle,
      'nadia_kessler': _back,
    },
    bailingOut: {'vela_ashworth'},
  ),

  TestScenario(
    id: 'refuse_to_bail',
    name: 'Refuse to Bail',
    item: '#2',
    goal:
        'The counter-play, which has never been equipped and fired outside a '
        'test. Rurik carries it and is on 1 health.',
    steps: [
      'Turn 1: tap Rurik and use Refuse to Bail on himself. Read what the '
          'interface says it will do before you commit.',
      'End the turn. Rurik is on 1 health at the Front, so the enemy should '
          'go for him.',
      'When he is hit, watch what happens instead of a Bail Out window.',
      'Take one more turn with him, then end it.',
    ],
    expect: [
      'Rurik stays standing on 1 health rather than dropping. No BAILING '
          'pill, no window.',
      'He can act normally for one more turn of his own.',
      'At the end of that turn he is gone for good, with no body to recall '
          'and no Trion Salvage for your squad.',
      'The log says all of that in plain words, and reads as a deliberate '
          'trade rather than a death.',
    ],
    caveat:
        'This one depends on the enemy choosing to attack Rurik and landing '
        'it. He is the lowest-health target standing at the front, so they '
        'usually do, but it may take two turns.',
    playerIds: _playerSquad,
    enemyIds: _enemySquad,
    kits: {
      'rurik_voss': _refuser,
      'kaito_reyes': _brawler,
      'mireille_song': _sniper,
      'vela_ashworth': _brawler,
      'ren_kobayashi': _brawler,
      'nadia_kessler': _sniper,
    },
    positions: {
      'rurik_voss': _front,
      'kaito_reyes': _back,
      'mireille_song': _back,
      'vela_ashworth': _front,
      'ren_kobayashi': _front,
      'nadia_kessler': _middle,
    },
    health: {'rurik_voss': 1},
  ),

  TestScenario(
    id: 'last_one_standing',
    name: 'The last one does not bail',
    item: '#2',
    goal:
        'A squad\'s final member has no window. The battle should end on '
        'the hit, not hold open to settle Trion nobody can spend.',
    steps: [
      'Two of the enemy squad are already gone. Nadia is the last, on 6 '
          'health, on their Front line.',
      'Kill her.',
    ],
    expect: [
      'No BAILING pill and no window. She simply falls.',
      'The battle ends immediately on that hit.',
      'No Trion Salvage is banked by either squad.',
      'The ending in the log reads as a victory, and is worded differently '
          'from the recall and destroy endings.',
    ],
    playerIds: _playerSquad,
    enemyIds: _enemySquad,
    kits: {
      'rurik_voss': _brawler,
      'kaito_reyes': _brawler,
      'mireille_song': _sniper,
      'vela_ashworth': _brawler,
      'ren_kobayashi': _brawler,
      'nadia_kessler': _brawler,
    },
    positions: {
      'rurik_voss': _front,
      'kaito_reyes': _front,
      'mireille_song': _middle,
      'nadia_kessler': _front,
    },
    health: {'nadia_kessler': 6},
    destroyed: {'vela_ashworth', 'ren_kobayashi'},
  ),
];
