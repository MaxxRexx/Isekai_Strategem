import 'package:battle_engine/battle_engine.dart';

import 'draft.dart';
import 'play_session.dart';
import 'scenario_script.dart';

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

  /// One word, or as near to one as the case allows.
  ///
  /// The working agreement's playtest shorthand addresses a scenario by name
  /// ("#TF - Bleed"), which only works if the name is short enough to type.
  /// What the scenario is *for* belongs in [goal], which has room for it.
  final String name;

  /// The work item this exercises, shown as a chip on the picker.
  final String item;

  /// One line on what this scenario is for.
  final String goal;

  /// What the tester should do, in order. Lazily built for the same reason
  /// as [expectations]: a step that names a distance should get it from the
  /// rule rather than from memory.
  final List<String> Function(TestScenario s) steps;
  List<String> get orderedSteps => steps(this);

  /// What should happen if the feature is right. Written so that a "no" is
  /// as easy to spot as a "yes".
  ///
  /// Built lazily from the scenario itself, so a claim about a distance is
  /// **computed by the same rule the game uses** rather than written out by
  /// hand. The first version of this was a plain list, and the "Read the
  /// board" brief shipped saying one screening pip and distances of 3 and 5
  /// where the game correctly showed two pips and 4 and 6. A brief that can
  /// disagree with the game is worse than no brief, because the tester
  /// believes it.
  final List<String> Function(TestScenario s) expect;

  /// The brief's expectations, with every number in them computed.
  List<String> get expectations => expect(this);

  /// A known reason this scenario might not play out as written, or null.
  /// Honest about the dice: some of these need an attack to land.
  final String? caveat;

  /// The same run as [steps], written so a machine can play it.
  ///
  /// [steps] and [expectations] are prose for a person: they say why the
  /// case matters and what to look for. This says what to do, precisely
  /// enough to execute, so `runScenarioScript` can play the scenario dozens
  /// of times over fixed dice and report what held. The judgement calls stay
  /// with the person; the mechanical checks stop needing one.
  ///
  /// Null on the retired scenarios, whose cases have already been confirmed.
  /// `scenario_script_test` refuses a live one without a script.
  final List<ScenarioStep>? script;

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

  /// Played, and behaved. Retired scenarios stay in this file but are kept
  /// out of the picker, because a tab full of cases that already passed
  /// buries the one that has not.
  ///
  /// They are not deleted, for two reasons. #4 re-prices the whole economy
  /// and #3 re-prices every duration, so these same boards will want
  /// re-running against the numbers that ship, and rebuilding them each time
  /// is the expensive way. And their assertions still run in
  /// `test_scenarios_test.dart`, which is what keeps their briefs honest.
  final bool retired;

  const TestScenario({
    required this.id,
    required this.name,
    required this.item,
    required this.goal,
    required this.steps,
    required this.expect,
    this.caveat,
    this.script,
    required this.playerIds,
    required this.enemyIds,
    required this.kits,
    this.positions = const {},
    this.health = const {},
    this.bailingOut = const {},
    this.destroyed = const {},
    this.startingTrion = 120,
    this.opponentProfileId = 'button_masher',
    this.retired = false,
  });

  bool _isPlayer(String id) => playerIds.contains(id);

  /// A status effect's duration, read from the catalogue so a brief cannot
  /// quote a number the game stopped using. This one was written when War
  /// Chant's Empowered lasted two turns and still said so after it became
  /// three, in the same scenario whose expectations said three.
  int durationOf(String statusEffectId) =>
      StatusEffectCatalog.defaultCatalog[statusEffectId].defaultDurationTurns ??
      0;

  /// Where [characterId] stands at the start, which is what the scenario
  /// pinned or, failing that, the position their kit's range bands derive.
  BattlePosition positionOf(String characterId) =>
      positions[characterId] ??
      startingPositionFor(
        loadoutFor(characterId).triggers.whereType<ActiveTrigger>().map(
              (t) => t.rangeTag,
            ),
      );

  /// Everyone on [characterId]'s side who is still on the board. A destroyed
  /// character is off it; a Bailing Out body is very much still on it, which
  /// is the whole of item #2's argument with item 1b.
  List<String> _squadOnBoardWith(String characterId) => [
        for (final id in _isPlayer(characterId) ? playerIds : enemyIds)
          if (!destroyed.contains(id)) id,
      ];

  /// How many bodies screen [targetId]: those of their own squad standing on
  /// a line strictly in front of them.
  int screensOn(String targetId) => BattleDistance.screensFor(
        positionOf(targetId),
        [for (final id in _squadOnBoardWith(targetId)) positionOf(id)],
      );

  /// The distance from [fromId] to [toId] at the start of the scenario,
  /// computed with `BattleDistance`, the engine's own rule. Asserted against
  /// a live battle in `test_scenarios_test.dart` for every pair in every
  /// scenario, so this cannot quietly drift from what the game does.
  int distanceBetween(String fromId, String toId) {
    if (_isPlayer(fromId) == _isPlayer(toId)) {
      return BattleDistance.betweenAllies(
        positionOf(fromId),
        positionOf(toId),
      );
    }
    return BattleDistance.betweenEnemies(
      positionOf(fromId),
      positionOf(toId),
      targetSquad: [for (final id in _squadOnBoardWith(toId)) positionOf(id)],
    );
  }

  /// "N: your step A, their step B, plus C screens", the workings the brief
  /// shows so a wrong number is legible rather than just wrong.
  String reachReading(String fromId, String toId) {
    final screens = screensOn(toId);
    final plural = screens == 1 ? 'screen' : 'screens';
    return '${distanceBetween(fromId, toId)}: your step '
        '${positionOf(fromId).step}, their step ${positionOf(toId).step}, '
        'plus $screens $plural';
  }

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
  /// [turnEngine] is the same seam `PlaySession.start` and `Battle` already
  /// offer, forwarded so a test can hand the scenario predictable dice.
  /// The Tests tab always leaves it null and gets the ordinary random engine.
  PlaySession start({TurnEngine? turnEngine}) => PlaySession.start(
        playerCharacterIds: playerIds,
        playerLoadouts: playerLoadouts,
        opponentCharacterIds: enemyIds,
        opponentProfileId: opponentProfileId,
        opponentLoadouts: enemyLoadouts,
        firstTurn: 'teamA',
        arrange: arrange,
        turnEngine: turnEngine,
      );

  /// Sets the board up on the built battle, immediately before the opening
  /// turn. Public so a test can arrange a battle without going through the
  /// interface.
  /// A scenario names characters by their roster id, which is what its briefs
  /// and its author read. The battle keys by combatant id, so this is the one
  /// place that translates.
  CharacterBattleState _state(Battle battle, String characterId) =>
      battle.stateOf(
        _isPlayer(characterId) ? battle.teamA : battle.teamB,
        characterId,
      );

  void arrange(Battle battle) {
    battle.teamA.trionPool.gain(startingTrion);
    battle.teamB.trionPool.gain(startingTrion);

    positions.forEach((id, position) {
      _state(battle, id).position = position;
    });
    health.forEach((id, value) {
      _state(battle, id).currentHealth = value;
    });

    // A body already on the board. Set directly rather than by dealing
    // damage, because `noteHealthChanged` is what turns a drop to zero into a
    // window and it has nothing to do here: a fresh state carries no reactive
    // effects for it to clear, and the window's own arming happens at the
    // turn boundary either way.
    for (final id in bailingOut) {
      final state = _state(battle, id);
      state.currentHealth = 0;
      state.bailOutState = BailOutState.bailingOut;
    }

    for (final id in destroyed) {
      final state = _state(battle, id);
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

/// The two support abilities item #5 spot-fixed, so a tester can see whether
/// a squad buff is worth an action.
const _supporter = [
  'war_chant',
  'guardians_aegis',
  'twin_fang_strike',
  'shatterpoint',
];

/// Two ways to bleed a target, which is the stacking status a Loadout can
/// reach today: Whirlwind Slash lands one stack, Rapid Fire strikes three
/// times and can land three.
const _stacker = [
  'whirlwind_slash',
  'rapid_fire',
  'twin_fang_strike',
  'guardians_aegis',
];

/// The cold half of item 3b's chain. Frost Lance chills what it hits, and a
/// second cold hit on a chilled target freezes it.
const _frostbite = [
  'frost_lance',
  'twin_fang_strike',
  'shatterpoint',
  'guardians_aegis',
];

/// The hammer that breaks the ice: Thunderclap Round is the reachable Thunder
/// attack, and Frozen shatters on Thunder.
const _thunder = [
  'thunderclap_round',
  'venom_needle',
  'shatterpoint',
  'guardians_aegis',
];

/// Carries the two abilities item #D is about: Mind Shatter silences an enemy
/// for one turn, and War Chant is a two-turn buff on yourself.
const _silencer = [
  'mind_shatter',
  'twin_fang_strike',
  'war_chant',
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

/// Every scenario ever written, retired or not. The tests validate all of
/// them; the picker shows [testScenarios].
final List<TestScenario> allScenarios = [
  TestScenario(
    id: 'support_pays_its_way',
    name: 'Buff',
    item: '#5',
    goal:
        'War Chant and Guardian\'s Aegis were self-buffs worth a quarter of '
        'the action they cost. They are area buffs now, and an area ability '
        'catches one line. The question for you is the one the pricing '
        'cannot answer: does spending a turn on either of them feel like it '
        'bought something?',
    steps: (s) => [
      'Rurik and Kaito both stand on your Middle line; Mireille is at the '
          'Back. Queue War Chant from Kaito and aim it at his own line.',
      'Resolve, and check who is carrying an EMPOWERED badge.',
      'Next turn, queue Guardian\'s Aegis the same way, end the turn, and '
          'let them attack into it.',
      'Play three or four turns and judge whether the turns you spent '
          'buffing paid for themselves.',
    ],
    expect: (s) => [
      'Rurik and Kaito both get EMPOWERED, because they share the line it '
          'was aimed at. Mireille does not: an area ability catches a line, '
          'not a squad, exactly as it does when the enemy uses one on you.',
      'That is the decision the ability asks for. Two characters standing '
          'together are worth buffing; a squad spread across three lines is '
          'not, and the same is true of every area attack in the game.',
      'EMPOWERED reads three turns, and the damage on your next attacks is '
          'visibly higher in the log.',
      'GUARDED and BRACED land on the same line, and the enemy turn after '
          'takes visibly less off those two.',
      'War Chant is on a one-turn cooldown now, so you can keep it up. '
          'Guardian\'s Aegis is still on two, deliberately: at one turn two '
          'defensive squads never finish each other off.',
    ],
    // The mechanical half of the brief. The judgement half ("did the turn
    // you spent buffing pay for itself") stays with the person.
    script: const [
      QueueAbility('kaito_reyes', 'war_chant',
          targets: ['kaito_reyes', 'rurik_voss']),
      ResolveOnly(),
      Carries('kaito_reyes', 'empowered'),
      Carries('rurik_voss', 'empowered'),
      DoesNotCarry('mireille_song', 'empowered'),
      Carries('kaito_reyes', 'empowered', turnsLeft: 3),
      EndTurn(),
      QueueAbility('kaito_reyes', 'guardians_aegis',
          targets: ['kaito_reyes', 'rurik_voss']),
      ResolveOnly(),
      Carries('kaito_reyes', 'guarded'),
      Carries('kaito_reyes', 'braced'),
      Carries('rurik_voss', 'guarded'),
      DoesNotCarry('mireille_song', 'guarded'),
    ],
    caveat:
        'This one is a judgement, not a pass or fail. The rule prices War '
        'Chant at 2.06 and the Aegis at 1.38 against a 2.0 to 3.0 band, and '
        'both prices assume the ability reaches all three targets it can '
        'hold, which is the same assumption every area attack in the '
        'catalogue is priced under. On a spread squad both are worth less '
        'than that. Wave 4 prices the lot again properly.',
    playerIds: _playerSquad,
    enemyIds: _enemySquad,
    kits: {
      'rurik_voss': _brawler,
      'kaito_reyes': _supporter,
      'mireille_song': _sniper,
      'vela_ashworth': _brawler,
      'ren_kobayashi': _brawler,
      'nadia_kessler': _sniper,
    },
    positions: {
      // Two on one line, one apart, so the brief can show what an area buff
      // reaches and what it does not.
      'rurik_voss': _middle,
      'kaito_reyes': _middle,
      'mireille_song': _back,
      'vela_ashworth': _front,
      'ren_kobayashi': _front,
      'nadia_kessler': _middle,
    },
    // Re-played after the area-targeting fix that this scenario's first
    // run exposed. #TWC, and the judgement half no runner can answer came
    // back with it: the buff is worth the turn it costs.
    retired: true,
  ),

  TestScenario(
    id: 'stacking_bleed',
    name: 'Bleed',
    item: '5b',
    goal:
        'Twelve statuses stack, capped at three, and a stack multiplies '
        'everything the status does. One badge, one timer, three times the '
        'damage. Check that the badge says how many are on there and that '
        'the fourth application does nothing.',
    steps: (s) => [
      'Queue Whirlwind Slash from Rurik at the enemy Front (Vela) and '
          'resolve. It strikes once, so it lands at most one stack.',
      'Tap the BLEEDING badge on Vela and read the tooltip.',
      'Next turn, queue Rapid Fire from Kaito at Vela. It strikes three '
          'times, and each strike that wins the contest adds a stack.',
      'Keep attacking her and watch the badge stop moving.',
    ],
    expect: (s) => [
      'The first application shows a plain badge with the turns left on it '
          'and no multiplier at all.',
      'Once a second stack lands the badge shows x2, then x3. There is only '
          'ever one badge and one timer, never two of either.',
      'It never shows x4. Three is the cap, and the timer still refreshes '
          'on every application after that.',
      'The tooltip on a stacked badge says everything the status does is '
          'multiplied by the count.',
      'The bleed damage at the start of her turn goes up with the count: '
          'three stacks tick three times what one does.',
    ],
    // Everything here sits behind an attack landing and then winning an
    // infliction contest, so these come back as DICE rather than PASSED.
    // What would be a failure is a check that never holds on any seed.
    script: const [
      QueueAbility('rurik_voss', 'whirlwind_slash', targets: ['vela_ashworth']),
      ResolveOnly(),
      Carries('vela_ashworth', 'bleeding', stacks: 1),
      EndTurn(),
      QueueAbility('kaito_reyes', 'rapid_fire', targets: ['vela_ashworth']),
      ResolveOnly(),
      Carries('vela_ashworth', 'bleeding', stacks: 2),
      Carries('vela_ashworth', 'bleeding', stacks: 3),
    ],
    caveat:
        'Every strike has to hit and then win the infliction contest to add '
        'a stack, so a turn can pass without the count moving. That is the '
        'contest, not the stacking.',
    playerIds: _playerSquad,
    enemyIds: _enemySquad,
    kits: {
      'rurik_voss': _stacker,
      'kaito_reyes': _stacker,
      'mireille_song': _sniper,
      'vela_ashworth': _brawler,
      'ren_kobayashi': _brawler,
      'nadia_kessler': _sniper,
    },
    positions: {
      'rurik_voss': _middle,
      'kaito_reyes': _middle,
      'mireille_song': _back,
      'vela_ashworth': _front,
      'ren_kobayashi': _middle,
      'nadia_kessler': _back,
    },
    // Re-played with the stack counts now printed in the log, which is
    // what the first run could not see. #TWC.
    retired: true,
  ),

  TestScenario(
    id: 'freeze_and_shatter',
    name: 'Freeze',
    item: '3b',
    goal:
        'The whole reaction chain in one turn. Chill a target, freeze the '
        'chill with a second cold hit, then break the ice with Thunder for '
        'double damage. Two reactions, neither of them rolled for.',
    steps: (s) => [
      'Queue Frost Lance from Rurik (Middle) at Vela on their Front line, '
          'distance ${s.distanceBetween('rurik_voss', 'vela_ashworth')}.',
      'Queue Frost Lance from Kaito (Middle) at Vela as well.',
      'Queue Thunderclap Round from Mireille (Back) at Vela, distance '
          '${s.distanceBetween('mireille_song', 'vela_ashworth')}.',
      'Resolve the turn and read the log from the top.',
    ],
    expect: (s) => [
      'The three resolve in the order Rurik, Kaito, Mireille. They are all '
          'attacks, so the tie is broken by Team Spirit distance from the '
          'midpoint, and that is the order it gives.',
      'Rurik lands CHILLED. Nothing reacts yet: there was nothing on her to '
          'react.',
      'Kaito hits a chilled target with Cold, and a REACTION line says '
          'Chilled becomes Frozen. It is not rolled for and it cannot be '
          'resisted.',
      'Mireille hits a frozen target with Thunder, and a second REACTION '
          'line says the ice shatters for double damage on that hit.',
      'Vela ends the turn without the Frozen badge. It was spent breaking.',
    ],
    script: const [
      QueueAbility('rurik_voss', 'frost_lance', targets: ['vela_ashworth']),
      QueueAbility('kaito_reyes', 'frost_lance', targets: ['vela_ashworth']),
      QueueAbility('mireille_song', 'thunderclap_round',
          targets: ['vela_ashworth']),
      ResolveOnly(),
      ReactionFired('Chilled', became: 'Frozen'),
      ReactionFired('Frozen'),
      DoesNotCarry('vela_ashworth', 'frozen'),
      // The confusion a playtest reported: the log said Chilled became
      // Frozen and Chilled was on her again. Both are true, and the line
      // has to say so.
      LogSays('the same attack applies Chilled again'),
    ],
    caveat:
        'Frost Lance still has to hit and win the infliction contest to apply '
        'Chilled in the first place, which is the one rolled step in the '
        'chain. If no CHILLED badge appears after Rurik, nothing later can '
        'react: re-run rather than reading it as a reaction fault.',
    playerIds: _playerSquad,
    enemyIds: _enemySquad,
    kits: {
      'rurik_voss': _frostbite,
      'kaito_reyes': _frostbite,
      'mireille_song': _thunder,
      'vela_ashworth': _brawler,
      'ren_kobayashi': _brawler,
      'nadia_kessler': _sniper,
    },
    positions: {
      'rurik_voss': _middle,
      'kaito_reyes': _middle,
      'mireille_song': _back,
      'vela_ashworth': _front,
      'ren_kobayashi': _middle,
      'nadia_kessler': _back,
    },
    // Re-played with Chilled and Frozen told apart in the log, which is
    // what put the "(I think)" on the first verdict. #TWC, so it is
    // settled.
    retired: true,
  ),

  TestScenario(
    id: 'one_turn_silence',
    name: 'Lock',
    item: '#D',
    goal:
        'A status that says one turn should take one whole turn away. Until '
        'item #D it took none: the count ran down at the start of its '
        'holder\'s turn, so a one-turn lock was removed before they acted '
        'and did nothing at all.',
    steps: (s) => [
      'Queue Mind Shatter from Kaito (Middle) at the enemy Front (Vela), '
          'which is Mid Range at distance '
          '${s.distanceBetween('kaito_reyes', 'vela_ashworth')}, and resolve '
          'the turn.',
      'If it landed, Vela shows a SILENCED badge. Tap it and read what it '
          'says is left.',
      'End your turn and watch what the enemy squad does.',
      'Take your next turn and check the badge is gone.',
    ],
    expect: (s) => [
      'The badge tooltip reads "One turn left: it wears off at the end of '
          'their next turn." No arithmetic, no warning that it is about to '
          'vanish unused.',
      'Vela does not act on the enemy turn. That is the whole point: one '
          'turn of Silenced costs exactly one action.',
      'The badge is gone by the time you act again, and it went at the end '
          'of their turn rather than the start of it.',
      'Nobody else on their squad is affected, and their turn otherwise '
          'plays normally.',
    ],
    caveat:
        'Mind Shatter has to hit and then win the infliction contest, so it '
        'can fail outright. If no SILENCED badge appears, the status never '
        'landed: re-run the scenario rather than reading it as a duration '
        'fault.',
    playerIds: _playerSquad,
    enemyIds: _enemySquad,
    kits: {
      'rurik_voss': _brawler,
      'kaito_reyes': _silencer,
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
      'ren_kobayashi': _middle,
      'nadia_kessler': _back,
    },
    // Played, and the verdict was "works correctly".
    retired: true,
  ),

  TestScenario(
    id: 'buff_lasts_your_turns',
    name: 'Duration',
    item: '#D',
    goal:
        'The other half of item #D. A two-turn buff on yourself should cover '
        'two of your own turns, counting from your next one, and the turn '
        'you cast it on is a free remainder rather than one of the two.',
    steps: (s) => [
      'Queue War Chant from Kaito on himself and resolve the turn. It is a '
          'squad buff now, so aim it at Kaito alone to keep this simple.',
      'Read the EMPOWERED badge on Kaito: it should say '
          '${s.durationOf('empowered')} turns left.',
      'End your turn. On your next turn the badge should still say '
          '${s.durationOf('empowered')}: the turn you cast it on is a free '
          'remainder and does not count.',
      'End that turn. Now it counts down one of your turns at a time, so it '
          'reads ${s.durationOf('empowered') - 1}, then '
          '${s.durationOf('empowered') - 2}, and is gone at the end of the '
          '${s.durationOf('empowered')}th of your turns after the cast.',
    ],
    expect: (s) => [
      'Right after casting, the badge says 3 turns left, counting your next '
          'one. It does not drop to 2 on the turn you cast it.',
      'It is still on Kaito for three of your own turns, not two.',
      'It wears off at the end of the third of those, so you never start a '
          'turn with a buff that is about to be taken away unused.',
      'The count only moves on your own turns. The enemy taking a turn does '
          'not spend one of yours.',
    ],
    // Item #D as arithmetic: cast, and it reads 3. One of your turns later
    // it reads 2, not 1. The enemy's turn in between spends nothing.
    script: const [
      QueueAbility('kaito_reyes', 'war_chant', targets: ['kaito_reyes']),
      ResolveOnly(),
      Carries('kaito_reyes', 'empowered', turnsLeft: 3),
      // Item #D itself: the turn it was cast on is a free remainder, so
      // ending it spends none of the three.
      EndTurn(),
      Carries('kaito_reyes', 'empowered', turnsLeft: 3),
      EndTurn(),
      Carries('kaito_reyes', 'empowered', turnsLeft: 2),
      EndTurn(),
      Carries('kaito_reyes', 'empowered', turnsLeft: 1),
      EndTurn(),
      DoesNotCarry('kaito_reyes', 'empowered'),
    ],
    playerIds: _playerSquad,
    enemyIds: _enemySquad,
    kits: {
      'rurik_voss': _brawler,
      'kaito_reyes': _silencer,
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
      'ren_kobayashi': _middle,
      'nadia_kessler': _back,
    },
    // Blocked on the first run: the buff could not be cast on the
    // intended target at all. Re-played after the targeting fix. #TWC.
    retired: true,
  ),

  TestScenario(
    id: 'read_the_board',
    retired: true,
    name: 'Board',
    item: '1b',
    goal:
        'Nothing to kill. Just check that the battlefield strip says what the '
        'screening rule actually computes.',
    steps: (s) => [
      'Look at the battlefield strip without doing anything.',
      'Tap each of your three characters in turn and read the distance to '
          'each enemy line.',
    ],
    expect: (s) => [
      'Your squad stands Front, Middle, Back. The enemy has two on their '
          'Front line and one on their Back, so their Middle line is empty.',
      'The empty enemy Middle line reads as a dash, not as a distance.',
      'The enemy Back line carries '
          '${s.screensOn('nadia_kessler')} screening pips, one per enemy '
          'standing on a line strictly in front of it.',
      'From Rurik at your Front, the enemy Front reads '
          '${s.distanceBetween('rurik_voss', 'vela_ashworth')} and the enemy '
          'Back reads ${s.reachReading('rurik_voss', 'nadia_kessler')}.',
      'From Mireille at your Back, that same enemy Back line reads '
          '${s.reachReading('mireille_song', 'nadia_kessler')}.',
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
    retired: true,
    name: 'Screen',
    item: '1b',
    goal:
        'Two enemies standing in front of a third should put that third out '
        'of Close Range reach entirely.',
    steps: (s) => [
      'Tap Rurik, at your Front line, and select Twin Fang Strike (Close '
          'Range).',
      'Try to aim it at Nadia Kessler on the enemy Back line.',
    ],
    expect: (s) => [
      'Nadia is not offered as a target.',
      'The strip shows her at distance '
          '${s.reachReading('rurik_voss', 'nadia_kessler')}. Close Range '
          'reaches 0 to 2.',
      'The ability, or the strip, says why in plain words rather than just '
          'greying out. Screening should be named, and so should the fix.',
      'Vela on their Front line reads '
          '${s.distanceBetween('rurik_voss', 'vela_ashworth')}, and Ren on '
          'their Middle reads '
          '${s.distanceBetween('rurik_voss', 'ren_kobayashi')}, both '
          'reachable. Only the far line is walled off.',
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
    retired: true,
    name: 'Body',
    item: '1b and #2',
    goal:
        'Killing a screen does not open the lane. The body left behind goes '
        'on screening until it is cleared or recalled, which is the single '
        'place these two items meet.',
    steps: (s) => [
      'Note the distance from Rurik to either enemy on the Back line, and '
          'the screening pips beside them.',
      'Turn 1: kill Vela at the enemy Front with Twin Fang Strike. She is on '
          '6 health.',
      'Look at the strip again before ending your turn.',
      'Turn 2: hit the body with any damaging ability to destroy it, then '
          'look at the strip once more.',
    ],
    expect: (s) => [
      'Vela drops and shows a colourless BAILING OUT pill, not a defeated '
          'state. That goes for your own squad as well as theirs.',
      'The distance to the Back line stays at '
          '${s.distanceBetween('rurik_voss', 'nadia_kessler')} and the '
          'screening pip stays, because her body is still standing on the '
          'line in front.',
      'Once the body is destroyed the distance falls by one, the pip goes, '
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
    retired: true,
    name: 'Bend',
    item: '1b',
    goal:
        'Breaking a screen in the same turn you shoot past it should never '
        'waste the shot. It bends to reach, and the squad pays next turn.',
    steps: (s) => [
      'Vela is already a Bailing Out body on the enemy Front line, screening '
          'Ren behind her.',
      'Tap Mireille at your Front line and queue Longshot (Long Range, '
          'reaches 2 to 4) at Ren. Ren is at distance '
          '${s.reachReading('mireille_song', 'ren_kobayashi')} right now, '
          'the body among them.',
      'Without ending your turn, tap Rurik and queue Twin Fang Strike at the '
          'body. Queue order matters: the body has to be cleared before the '
          'shot resolves, so make sure Rurik\'s strike sits above the '
          'Longshot in the queue.',
      'End the turn and read the log.',
    ],
    expect: (s) => [
      'The body is destroyed first, which drops Ren to distance '
          '${s.distanceBetween('mireille_song', 'ren_kobayashi') - 1}, under '
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
    retired: true,
    name: 'Window',
    item: '#2',
    goal:
        'The contested window itself. One setup, two endings, and the fork is '
        'the whole point of the item.',
    steps: (s) => [
      'Turn 1: kill Vela at the enemy Front. She is on 6 health.',
      'End your turn and let the enemy have theirs. The body should still be '
          'standing afterwards.',
      'Turn 2 is the window. Pick one: hit the body with any damaging '
          'ability, or leave it alone and end the turn.',
      'Run the scenario twice, once each way.',
    ],
    expect: (s) => [
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
    retired: true,
    name: 'Targeting',
    item: '#2',
    goal:
        'A body can be destroyed but not debuffed, healed or charmed. Check '
        'the target picker agrees.',
    steps: (s) => [
      'Vela is already a body on the enemy Front line.',
      'Tap Kaito and select Charm Whisper, which deals no damage.',
      'Look at who it offers as targets.',
      'Now select Twin Fang Strike on the same character and compare.',
    ],
    expect: (s) => [
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
    retired: true,
    name: 'Refuse',
    item: '#2',
    goal:
        'The counter-play, which has never been equipped and fired outside a '
        'test. Rurik carries it and is on 1 health.',
    steps: (s) => [
      'Turn 1: tap Rurik and use Refuse to Bail on himself. Read what the '
          'interface says it will do before you commit.',
      'End the turn. Rurik is on 1 health at the Front, so the enemy should '
          'go for him.',
      'When he is hit, watch what happens instead of a Bail Out window.',
      'Take one more turn with him, then end it.',
    ],
    expect: (s) => [
      'Rurik stays standing on 1 health rather than dropping. No BAILING OUT '
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
    id: 'mirror_match',
    retired: true,
    name: 'Mirror',
    item: '#14',
    goal:
        'Both squads field the same three characters. Until item #14 the draft '
        'screens forbade this, because the two of them shared one battle '
        'state.',
    steps: (s) => [
      'Look at both squad panels. Every character appears twice, once on each '
          'side.',
      'Attack the enemy Ilona Vance with your own Ilona Vance.',
      'Read the log line, then check your own Ilona\'s health.',
    ],
    expect: (s) => [
      'Your Ilona reads "Ilona Vance (yours)" and theirs reads "Ilona Vance '
          '(theirs)". Only a mirrored character is named this way; in an '
          'ordinary battle the names are plain.',
      'The log names both of them unambiguously, so "Ilona Vance hits Ilona '
          'Vance" never appears.',
      'Damage lands on theirs only. Your own Ilona is untouched, which is the '
          'whole bug this item fixes.',
      'A status, a move or a Bail Out on one of them does nothing to the '
          'other.',
      'The battle plays and concludes normally.',
    ],
    caveat:
        'The attack still has to land. Both Ilonas have Defense 11, so expect '
        'to miss more often than in the other scenarios.',
    playerIds: const ['ilona_vance', 'marren_osei', 'bastian_cole'],
    enemyIds: const ['ilona_vance', 'marren_osei', 'bastian_cole'],
    kits: {
      for (final id in const ['ilona_vance', 'marren_osei', 'bastian_cole'])
        id: _brawler,
    },
    positions: const {},
  ),

  TestScenario(
    id: 'last_one_standing',
    retired: true,
    name: 'Last',
    item: '#2',
    goal:
        'A squad\'s final member has no window. The battle should end on '
        'the hit, not hold open to settle Trion nobody can spend.',
    steps: (s) => [
      'Two of the enemy squad are already gone. Nadia is the last, on 6 '
          'health, on their Front line.',
      'Kill her.',
    ],
    expect: (s) => [
      'No BAILING OUT pill and no window. She simply falls.',
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

/// What the Tests tab offers: the cases that have **not** yet been confirmed.
///
/// Emptying itself is the intended end state for a round of testing. Wave 1's
/// features add their own scenarios here as they land; everything already
/// played is in [allScenarios] with `retired: true`.
final List<TestScenario> testScenarios =
    allScenarios.where((s) => !s.retired).toList();
