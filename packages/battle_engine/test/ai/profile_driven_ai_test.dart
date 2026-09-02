import 'dart:math';

import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// A [Random] that always returns [fixedDouble] for `nextDouble()`, so a
/// test can force (or forbid) `ProfileDrivenAi`'s mistake-chance roll
/// deterministically.
class _FixedDoubleRandom implements Random {
  final double fixedDouble;
  const _FixedDoubleRandom(this.fixedDouble);

  @override
  double nextDouble() => fixedDouble;

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}

Team _team(String prefix) => Team(
      id: '$prefix-team',
      characters: [
        testCharacter(id: '$prefix-1'),
        testCharacter(id: '$prefix-2'),
        testCharacter(id: '$prefix-3'),
      ],
    );

void main() {
  group('ProfileDrivenAi ability priority', () {
    test('highestDamage picks the strongest usable ability', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);
      final ai = ProfileDrivenAi(AiProfile.theExecutioner,
          random: const _FixedDoubleRandom(1.0));

      final weak = testTrigger(
          id: 'weak', damage: const DiceExpression(0, 1, flatBonus: 1));
      final strong = testTrigger(
          id: 'strong', damage: const DiceExpression(0, 1, flatBonus: 50));

      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [weak, strong],
        'a-2': [],
        'a-3': [],
      });

      expect(results.single.triggerId, 'strong');
    });

    test('aoeFavoring picks an AOE ability over a higher-damage single', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);
      final ai = ProfileDrivenAi(AiProfile.theBlastRadius,
          random: const _FixedDoubleRandom(1.0));

      final singleStrong = testTrigger(
        id: 'single_strong',
        abilitySubtype: AbilitySubtype.single,
        damage: const DiceExpression(0, 1, flatBonus: 50),
      );
      final aoeWeak = testTrigger(
        id: 'aoe_weak',
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        damage: const DiceExpression(0, 1, flatBonus: 1),
      );

      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [singleStrong, aoeWeak],
        'a-2': [],
        'a-3': [],
      });

      expect(results.single.triggerId, 'aoe_weak');
    });

    test(
        'debuffFocused picks a status-inflicting ability over a stronger '
        'plain attack', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);
      final ai = ProfileDrivenAi(AiProfile.theAfflictor,
          random: const _FixedDoubleRandom(1.0));

      final plainStrong = testTrigger(
        id: 'plain_strong',
        damage: const DiceExpression(0, 1, flatBonus: 50),
      );
      final debuffWeak = testTrigger(
        id: 'debuff_weak',
        damage: const DiceExpression(0, 1, flatBonus: 1),
        inflictedStatusEffects: const [StatusEffectApplication('poisoned')],
      );

      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [plainStrong, debuffWeak],
        'a-2': [],
        'a-3': [],
      });

      expect(results.single.triggerId, 'debuff_weak');
    });

    test(
        'blackTriggerFavoring picks the equipped Black Trigger ability '
        'over a stronger regular one', () {
      final blackTriggerAbility = testTrigger(
        id: 'bt_ability',
        damage: const DiceExpression(0, 1, flatBonus: 1),
      );
      final blackTrigger = BlackTrigger(
        id: 'bt-1',
        name: 'Test BT',
        type: BlackTriggerType.attack,
        equipCost: 20,
        activeAbilities: [blackTriggerAbility],
      );
      final gambler = testCharacter(id: 'a-1');
      final gamblerWithBt = Character(
        id: gambler.id,
        name: gambler.name,
        type: gambler.type,
        baseStats: gambler.baseStats,
        blackTrigger: blackTrigger,
      );
      final teamA = Team(id: 'a-team', characters: [
        gamblerWithBt,
        testCharacter(id: 'a-2'),
        testCharacter(id: 'a-3'),
      ]);
      final battle = Battle(teamA: teamA, teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);
      final ai = ProfileDrivenAi(AiProfile.theGambler,
          random: const _FixedDoubleRandom(1.0));

      final regularStrong = testTrigger(
        id: 'regular_strong',
        damage: const DiceExpression(0, 1, flatBonus: 50),
      );

      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [regularStrong, blackTriggerAbility],
        'a-2': [],
        'a-3': [],
      });

      expect(results.single.triggerId, 'bt_ability');
    });
  });

  group('ProfileDrivenAi target priority', () {
    test('lowestHealth focuses the weakest legal opponent', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);
      battle.states['b-1']!.currentHealth = 80;
      battle.states['b-2']!.currentHealth = 10;
      battle.states['b-3']!.currentHealth = 50;
      final ai = ProfileDrivenAi(AiProfile.theExecutioner,
          random: const _FixedDoubleRandom(1.0));

      final trigger =
          testTrigger(damage: const DiceExpression(0, 1, flatBonus: 5));
      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [trigger],
        'a-2': [],
        'a-3': [],
      });

      expect(
        results.single.useResult.targetResults.single.targetCharacterId,
        'b-2',
      );
    });

    test('matchupAware weighs Armor/Defense, not just raw health', () {
      // b-1 has slightly more health but far less Armor/Defense, so it's
      // the more attractive kill target for a matchup-aware profile.
      final tankyCharacter = Character(
        id: 'b-2',
        name: 'Tanky',
        type: CharacterType.defense,
        baseStats: testStats(armor: 50, defense: 50),
      );
      final teamB = Team(id: 'b-team', characters: [
        testCharacter(id: 'b-1'),
        tankyCharacter,
        testCharacter(id: 'b-3'),
      ]);
      final battle = Battle(teamA: _team('a'), teamB: teamB);
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);
      battle.states['b-1']!.currentHealth = 40;
      battle.states['b-2']!.currentHealth = 45;

      final ai = ProfileDrivenAi(AiProfile.theTactician,
          random: const _FixedDoubleRandom(1.0));
      final trigger =
          testTrigger(damage: const DiceExpression(0, 1, flatBonus: 5));
      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [trigger],
        'a-2': [],
        'a-3': [],
      });

      expect(
        results.single.useResult.targetResults.single.targetCharacterId,
        'b-1',
      );
    });
  });

  group('ProfileDrivenAi Expert lookahead', () {
    // A: low matchup score (favored by plain matchupAware sorting) but
    // its health (15) survives this trigger's ~10 predicted damage.
    // B: worse matchup score (high Defense drags it down) but its
    // health (8) would actually die to that same ~10 predicted damage.
    Team lookaheadOpponents() => Team(id: 'b-team', characters: [
          Character(
            id: 'b-a',
            name: 'Survivor',
            type: CharacterType.attack,
            baseStats: testStats(armor: 0, defense: 0, maxHealth: 15),
          ),
          Character(
            id: 'b-b',
            name: 'Killable',
            type: CharacterType.attack,
            baseStats: testStats(armor: 0, defense: 100, maxHealth: 8),
          ),
          testCharacter(id: 'b-c'),
        ]);

    test(
        'Expert prefers a target it can actually kill over the normal '
        'matchup-aware top pick', () {
      final battle = Battle(teamA: _team('a'), teamB: lookaheadOpponents());
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);
      battle.states['b-a']!.currentHealth = 15;
      battle.states['b-b']!.currentHealth = 8;

      final ai = ProfileDrivenAi(AiProfile.theGrandmaster,
          random: const _FixedDoubleRandom(1.0));
      final trigger =
          testTrigger(damage: const DiceExpression(0, 1, flatBonus: 10));
      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [trigger],
        'a-2': [],
        'a-3': [],
      });

      expect(
        results.single.useResult.targetResults.single.targetCharacterId,
        'b-b',
      );
    });

    test(
        'Professional (same matchupAware targeting, no lookahead) sticks '
        "with the normal top pick even though it can't kill it", () {
      final battle = Battle(teamA: _team('a'), teamB: lookaheadOpponents());
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);
      battle.states['b-a']!.currentHealth = 15;
      battle.states['b-b']!.currentHealth = 8;

      final ai = ProfileDrivenAi(AiProfile.theTactician,
          random: const _FixedDoubleRandom(1.0));
      final trigger =
          testTrigger(damage: const DiceExpression(0, 1, flatBonus: 10));
      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [trigger],
        'a-2': [],
        'a-3': [],
      });

      expect(
        results.single.useResult.targetResults.single.targetCharacterId,
        'b-a',
      );
    });
  });

  group('ProfileDrivenAi bespoke habits', () {
    test(
        'The Berserker keeps targeting whoever it last damaged, ahead of '
        'its normal firstAvailable priority', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);
      battle.states['a-1']!.lastDamagedTargetId = 'b-3';

      final ai = ProfileDrivenAi(AiProfile.theBerserker,
          random: const _FixedDoubleRandom(1.0));
      final trigger =
          testTrigger(damage: const DiceExpression(0, 1, flatBonus: 5));
      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [trigger],
        'a-2': [],
        'a-3': [],
      });

      expect(
        results.single.useResult.targetResults.single.targetCharacterId,
        'b-3',
      );
    });

    test(
        'The Grudge Holder targets whoever dealt the most cumulative '
        'damage, not whoever has the highest Attack stat', () {
      final highAttackLowThreat = Character(
        id: 'b-1',
        name: 'Glass Cannon',
        type: CharacterType.attack,
        baseStats: testStats(attack: 999),
      );
      final teamB = Team(id: 'b-team', characters: [
        highAttackLowThreat,
        testCharacter(id: 'b-2'),
        testCharacter(id: 'b-3'),
      ]);
      final battle = Battle(teamA: _team('a'), teamB: teamB);
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);
      battle.states['b-2']!.cumulativeDamageDealt = 500;

      final ai = ProfileDrivenAi(AiProfile.theGrudgeHolder,
          random: const _FixedDoubleRandom(1.0));
      final trigger =
          testTrigger(damage: const DiceExpression(0, 1, flatBonus: 5));
      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [trigger],
        'a-2': [],
        'a-3': [],
      });

      expect(
        results.single.useResult.targetResults.single.targetCharacterId,
        'b-2',
      );
    });

    test(
        'The Copycat prefers a usable ability matching the category the '
        "opponent team most recently used, over its normal highest-damage "
        'pick', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);
      battle.states['b-1']!.lastActiveTriggerCategory = TriggerCategory.trapper;

      final ai = ProfileDrivenAi(AiProfile.theCopycat,
          random: const _FixedDoubleRandom(1.0));
      final strongAttacker = testTrigger(
        id: 'strong_attacker',
        category: TriggerCategory.attacker,
        damage: const DiceExpression(0, 1, flatBonus: 50),
      );
      final weakTrapper = testTrigger(
        id: 'weak_trapper',
        category: TriggerCategory.trapper,
        damage: const DiceExpression(0, 1, flatBonus: 1),
      );

      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [strongAttacker, weakTrapper],
        'a-2': [],
        'a-3': [],
      });

      expect(results.single.triggerId, 'weak_trapper');
    });

    test(
        'The Sharpshooter overvalues an at-range option in battle, not just '
        'when drafting a Loadout', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);

      final ai = ProfileDrivenAi(AiProfile.theSharpshooter,
          random: const _FixedDoubleRandom(1.0));
      final close = testTrigger(
        id: 'close',
        rangeTag: RangeTag.close,
        damage: const DiceExpression(0, 1, flatBonus: 10),
      );
      final long = testTrigger(
        id: 'long',
        rangeTag: RangeTag.long,
        damage: const DiceExpression(0, 1, flatBonus: 10),
      );

      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [close, long],
        'a-2': [],
        'a-3': [],
      });

      expect(results.single.triggerId, 'long');
    });

    test(
        'The Turtle keeps buffing itself even when the buff would be a '
        'no-op, unlike a profile with the normal usefulness gate', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);
      battle.turnEngine.statusEffectEngine
          .apply(battle.states['a-1']!, 'guarded');

      final ai = ProfileDrivenAi(AiProfile.theTurtle,
          random: const _FixedDoubleRandom(1.0));
      final buff = testTrigger(
        id: 'buff',
        targetAffiliation: TargetAffiliation.self,
        includeDamage: false,
        inflictedStatusEffects: const [StatusEffectApplication('guarded')],
      );
      final attack = testTrigger(
        id: 'attack',
        damage: const DiceExpression(0, 1, flatBonus: 50),
      );

      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [buff, attack],
        'a-2': [],
        'a-3': [],
      });

      expect(results.single.triggerId, 'buff');
    });

    test(
        'The Sweeper switches to AOE once two or more enemies are in kill '
        'range together', () {
      final teamB = Team(id: 'b-team', characters: [
        Character(
          id: 'b-1',
          name: 'Fragile A',
          type: CharacterType.attack,
          baseStats: testStats(armor: 0, defense: 0, maxHealth: 100),
        ),
        Character(
          id: 'b-2',
          name: 'Fragile B',
          type: CharacterType.attack,
          baseStats: testStats(armor: 0, defense: 0, maxHealth: 100),
        ),
        Character(
          id: 'b-3',
          name: 'Sturdy',
          type: CharacterType.attack,
          baseStats: testStats(armor: 0, defense: 0, maxHealth: 100),
        ),
      ]);
      final battle = Battle(teamA: _team('a'), teamB: teamB);
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);
      battle.states['b-1']!.currentHealth = 1;
      battle.states['b-2']!.currentHealth = 1;
      battle.states['b-3']!.currentHealth = 100;

      final ai = ProfileDrivenAi(AiProfile.theSweeper,
          random: const _FixedDoubleRandom(1.0));
      final aoeWeak = testTrigger(
        id: 'aoe_weak',
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        damage: const DiceExpression(0, 1, flatBonus: 1),
      );
      final singleStrong = testTrigger(
        id: 'single_strong',
        abilitySubtype: AbilitySubtype.single,
        damage: const DiceExpression(0, 1, flatBonus: 100),
      );

      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [singleStrong, aoeWeak],
        'a-2': [],
        'a-3': [],
      });

      expect(results.single.triggerId, 'aoe_weak');
    });

    test(
        'The Sweeper stays on single-target focus fire when only one enemy '
        'is actually in kill range', () {
      final teamB = Team(id: 'b-team', characters: [
        Character(
          id: 'b-1',
          name: 'Fragile A',
          type: CharacterType.attack,
          baseStats: testStats(armor: 0, defense: 0, maxHealth: 100),
        ),
        Character(
          id: 'b-2',
          name: 'Sturdy A',
          type: CharacterType.attack,
          baseStats: testStats(armor: 0, defense: 0, maxHealth: 100),
        ),
        Character(
          id: 'b-3',
          name: 'Sturdy B',
          type: CharacterType.attack,
          baseStats: testStats(armor: 0, defense: 0, maxHealth: 100),
        ),
      ]);
      final battle = Battle(teamA: _team('a'), teamB: teamB);
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);
      battle.states['b-1']!.currentHealth = 1;
      battle.states['b-2']!.currentHealth = 100;
      battle.states['b-3']!.currentHealth = 100;

      final ai = ProfileDrivenAi(AiProfile.theSweeper,
          random: const _FixedDoubleRandom(1.0));
      final aoeWeak = testTrigger(
        id: 'aoe_weak',
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        damage: const DiceExpression(0, 1, flatBonus: 1),
      );
      final singleStrong = testTrigger(
        id: 'single_strong',
        abilitySubtype: AbilitySubtype.single,
        damage: const DiceExpression(0, 1, flatBonus: 100),
      );

      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [singleStrong, aoeWeak],
        'a-2': [],
        'a-3': [],
      });

      expect(results.single.triggerId, 'single_strong');
    });

    test(
        'The Prodigy switches to AOE when multiple enemies are alive, even '
        'though its base priority is otherwise damage-driven', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);

      final ai = ProfileDrivenAi(AiProfile.theProdigy,
          random: const _FixedDoubleRandom(1.0));
      final singleStrong = testTrigger(
        id: 'single_strong',
        abilitySubtype: AbilitySubtype.single,
        damage: const DiceExpression(0, 1, flatBonus: 50),
      );
      final aoeWeak = testTrigger(
        id: 'aoe_weak',
        abilityType: AbilityType.melee,
        abilitySubtype: AbilitySubtype.aoe,
        targetCount: 3,
        damage: const DiceExpression(0, 1, flatBonus: 1),
      );

      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [singleStrong, aoeWeak],
        'a-2': [],
        'a-3': [],
      });

      expect(results.single.triggerId, 'aoe_weak');
    });

    test(
        'The Prodigy falls back to setting up a debuff when only one enemy '
        'remains and it has no status effects yet', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);
      battle.states['b-2']!.currentHealth = 0;
      battle.states['b-3']!.currentHealth = 0;

      final ai = ProfileDrivenAi(AiProfile.theProdigy,
          random: const _FixedDoubleRandom(1.0));
      final plainStrong = testTrigger(
        id: 'plain_strong',
        damage: const DiceExpression(0, 1, flatBonus: 50),
      );
      final debuffWeak = testTrigger(
        id: 'debuff_weak',
        damage: const DiceExpression(0, 1, flatBonus: 1),
        inflictedStatusEffects: const [StatusEffectApplication('poisoned')],
      );

      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [plainStrong, debuffWeak],
        'a-2': [],
        'a-3': [],
      });

      expect(results.single.triggerId, 'debuff_weak');
    });
  });

  group('ProfileDrivenAi mistake chance', () {
    test(
        'a forced mistake picks a different ability than the profile '
        'would normally choose', () {
      final battle = Battle(teamA: _team('a'), teamB: _team('b'));
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);

      // nextDouble() always returns 0.0, which is below any positive
      // mistake chance, so the ability choice is forced into the
      // mistake branch; nextInt always returns 0, so the "random" pick
      // is deterministically whichever equipped trigger is listed first
      // - the weak one here, not the highestDamage profile's normal pick.
      final ai = ProfileDrivenAi(AiProfile.theExecutioner,
          random: const _FixedDoubleRandom(0.0));

      final weak = testTrigger(
          id: 'weak', damage: const DiceExpression(0, 1, flatBonus: 1));
      final strong = testTrigger(
          id: 'strong', damage: const DiceExpression(0, 1, flatBonus: 50));

      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [weak, strong],
        'a-2': [],
        'a-3': [],
      });

      expect(results.single.triggerId, 'weak');
    });
  });

  group('ProfileDrivenAi FAT policy', () {
    Battle fatBattle() {
      final character = testCharacter(
          id: 'a-1', stats: testStats(fatChance: 100, teamSpirit: 50));
      final teamA = Team(id: 'a-team', characters: [
        character,
        testCharacter(id: 'a-2'),
        testCharacter(id: 'a-3'),
      ]);
      final battle = Battle(
        teamA: teamA,
        teamB: _team('b'),
        turnEngine:
            TurnEngine(fatEngine: FatEngine(diceRoller: DiceRoller(Random(2)))),
      );
      battle.teamA.trionPool.gain(1000);
      stockEveryTrionType(battle.teamA, 20);
      var fatTriggered = false;
      for (var i = 0; i < 20 && !fatTriggered; i++) {
        battle.states['a-1']!.fatCooldownRemaining = 0;
        fatTriggered = battle.turnEngine.rollFatTrigger(battle.states['a-1']!);
      }
      expect(fatTriggered, isTrue);
      return battle;
    }

    test('neverVoluntary stops after one ability even when FAT allows more',
        () {
      final battle = fatBattle();
      final ai = ProfileDrivenAi(AiProfile.theTurtle,
          random: const _FixedDoubleRandom(1.0));
      final trigger = testTrigger(
          trionCost: 0,
          cooldownTurns: 0,
          damage: const DiceExpression(0, 1, flatBonus: 5));

      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [trigger],
        'a-2': [],
        'a-3': [],
      });

      expect(results, hasLength(1));
    });

    test('alwaysChain keeps going for every legal action FAT allows', () {
      final battle = fatBattle();
      final ai = ProfileDrivenAi(AiProfile.theExecutioner,
          random: const _FixedDoubleRandom(1.0));
      final trigger = testTrigger(
          trionCost: 0,
          cooldownTurns: 0,
          damage: const DiceExpression(0, 1, flatBonus: 5));

      final results = ai.takeTurn(battle, equippedActiveTriggers: {
        'a-1': [trigger],
        'a-2': [],
        'a-3': [],
      });

      expect(results, hasLength(3));
    });
  });
}
