import 'package:battle_engine/battle_engine.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

/// Item 1b: the parts of screening that only show up on a real battle.
///
/// The arithmetic lives in `battle_position_test`. This file covers what the
/// rule does once it is wired into the engine: that a live battle always has
/// the squad wiring screening reads, that area attacks inherit screening
/// without being taught it, and that traps deliberately do not.
void main() {
  /// Deterministic dice: two of these tests turn on an attack actually
  /// landing, and leaving that to the shuffle makes them fail perhaps one run
  /// in fifty, which is exactly the kind of test that erodes trust in a suite.
  Battle twoSquads() {
    final roster = CharacterRoster.defaultRoster;
    return Battle(
      turnEngine: TurnEngine(
        combatEngine:
            CombatEngine(diceRoller: DiceRoller(const FixedRandom(19))),
        statusEffectEngine:
            StatusEffectEngine(diceRoller: DiceRoller(const FixedRandom(19))),
      ),
      teamA: Team(
        id: 'a',
        characters: [
          roster['kaito_reyes'],
          roster['vela_ashworth'],
          roster['dross'],
        ],
        trionPool: TrionPool(current: 500, cap: 500),
      ),
      teamB: Team(
        id: 'b',
        characters: [
          roster['marren_osei'],
          roster['ilona_vance'],
          roster['bastian_cole'],
        ],
        trionPool: TrionPool(current: 500, cap: 500),
      ),
    );
  }

  void setLines(Battle battle, Map<String, BattlePosition> lines) {
    lines.forEach((id, line) => battle.states[id]!.position = line);
  }

  group('the squad wiring screening depends on', () {
    test('a real Battle always wires teammates, on both sides', () {
      // Screening reads `teammates`, which only the Battle constructor sets
      // up. A standalone harness may leave it empty, and then nobody screens
      // anybody, which is exactly the pre-1b behaviour and is why almost every
      // existing engine test kept passing. This guards the case that matters:
      // a live battle must never silently lose screening.
      final battle = twoSquads();
      for (final team in [battle.teamA, battle.teamB]) {
        for (final character in team.characters) {
          final state = battle.states[character.id]!;
          expect(state.teammates, hasLength(2),
              reason: '${character.id} must know its own squad');
          expect(state.teammates.map((t) => t.character.id),
              isNot(contains(character.id)),
              reason: 'nobody is their own teammate, or they would screen '
                  'themselves');
        }
      }
    });

    test('screeningLinesFor counts only living squadmates', () {
      final battle = twoSquads();
      setLines(battle, {
        'marren_osei': BattlePosition.front,
        'ilona_vance': BattlePosition.front,
        'bastian_cole': BattlePosition.back,
      });
      final sniper = battle.states['bastian_cole']!;
      expect(battle.turnEngine.screeningLinesFor(sniper), hasLength(2));

      battle.states['marren_osei']!.currentHealth = 0;
      expect(battle.turnEngine.screeningLinesFor(sniper), hasLength(1),
          reason: 'a body on the floor is not in the way');
    });
  });

  group('area attacks inherit screening without being taught it', () {
    test('a blast cannot catch a screened enemy it could otherwise reach', () {
      final battle = twoSquads();
      final attacker = battle.states['kaito_reyes']!
        ..position = BattlePosition.front;
      setLines(battle, {
        'marren_osei': BattlePosition.front,
        'ilona_vance': BattlePosition.front,
        'bastian_cole': BattlePosition.back,
      });
      final sniper = battle.states['bastian_cole']!;

      final blast = testTrigger(
        id: 'blast',
        rangeTag: RangeTag.close,
        attackSubtype: AttackSubtype.aoe,
        targetCount: 3,
        damage: const DiceExpression(1, 4, flatBonus: 40),
      );

      // Unscreened, the sniper's back line sits at 2 and Close Range's
      // widened window reaches it. Two bodies in front put them at 4.
      expect(battle.turnEngine.distanceBetween(attacker, sniper), 4);
      expect(battle.turnEngine.canReach(attacker, sniper, blast), isFalse);

      final result = battle.turnEngine.resolveAbilityUse(
        attacker: attacker,
        trigger: blast,
        targets: [
          sniper,
          battle.states['marren_osei']!,
          battle.states['ilona_vance']!,
        ],
      );
      final hit = result.targetResults.map((r) => r.targetCharacterId).toSet();
      expect(hit, isNot(contains('bastian_cole')),
          reason: 'an area attack is still an attack, and screening applies');
      expect(hit, containsAll(['marren_osei', 'ilona_vance']),
          reason: 'the unscreened pair are caught as normal');
    });
  });

  group('traps deliberately ignore screening', () {
    ActiveTrigger deadfall() => BlackTriggerCatalog
        .defaultCatalog['paradox_shard']
        .activeAbilities
        .firstWhere((a) => a.id == 'paradox_shard_deadfall');

    ActiveTrigger deathLedger() =>
        TriggerCatalog.defaultCatalog['death_ledger'] as ActiveTrigger;

    bool armed(Battle battle, String holderId, ReactiveKind kind) =>
        battle.states[holderId]!.reactiveEffects.any((r) => r.kind == kind);

    test('a screen arriving after the trap is planted does not save them', () {
      // The decided reading: a trap is a hazard already attached to its
      // target, and squadmates shuffling about in front of them does not undo
      // it. This is the one distance in the game measured without screens.
      final battle = twoSquads();
      setLines(battle, {
        for (final c in battle.teamA.characters) c.id: BattlePosition.back,
        for (final c in battle.teamB.characters) c.id: BattlePosition.back,
      });
      final caster = battle.states['dross']!;
      final sniper = battle.states['bastian_cole']!;

      // Camped, nobody screens anybody: 2 + 2 = 4, inside Long Range.
      expect(battle.turnEngine.canTarget(caster, sniper, trigger: deadfall()),
          isTrue);
      battle.turnEngine.resolveAbilityUse(
        attacker: caster,
        trigger: deadfall(),
        targets: [sniper],
      );
      expect(armed(battle, 'bastian_cole', ReactiveKind.trapOnAction), isTrue);

      // Two of their squad step up and screen the sniper, which would put
      // them at 6 if traps counted screens.
      setLines(battle, {
        'marren_osei': BattlePosition.front,
        'ilona_vance': BattlePosition.front,
      });
      expect(battle.turnEngine.distanceBetween(caster, sniper), 6,
          reason: 'every other distance in the game counts the screens');

      final shot = TriggerCatalog.defaultCatalog['longshot'] as ActiveTrigger;
      final victim = battle.states['kaito_reyes']!;
      final before = sniper.currentHealth;
      battle.turnEngine.resolveAbilityUse(
        attacker: sniper,
        trigger: shot,
        targets: [victim],
      );

      expect(sniper.currentHealth, lessThan(before),
          reason: 'the trap fires: bodies in front do not unstick it');
      expect(armed(battle, 'bastian_cole', ReactiveKind.trapOnAction), isFalse,
          reason: 'and it is spent');
    });

    test('but retreating out of the band you armed from does drop a trap', () {
      // The two lines still count, so a trap is not unconditional. Death
      // Ledger did not use to ask this question at all, which read as an
      // oversight rather than as a rule; now every enemy-placed trap asks it.
      final battle = twoSquads();
      setLines(battle, {
        for (final c in battle.teamA.characters) c.id: BattlePosition.back,
        for (final c in battle.teamB.characters) c.id: BattlePosition.front,
      });
      final caster = battle.states['dross']!;
      final holder = battle.states['bastian_cole']!;

      // My back line to their front line is 2, inside Mid Range 1 to 3.
      expect(battle.turnEngine.canTarget(caster, holder, trigger: deathLedger()),
          isTrue);
      battle.turnEngine.resolveAbilityUse(
        attacker: caster,
        trigger: deathLedger(),
        targets: [holder],
      );
      expect(armed(battle, 'bastian_cole', ReactiveKind.nullifyAoe), isTrue);

      // They fall back to their own back line: armed from step 2, holder now
      // on step 2, so 4, outside Mid Range.
      holder.position = BattlePosition.back;

      final blast =
          TriggerCatalog.defaultCatalog['frag_grenade'] as ActiveTrigger;
      final victims = [
        for (final c in battle.teamA.characters) battle.states[c.id]!,
      ];
      for (final v in victims) {
        v.position = BattlePosition.front;
      }
      final before = {
        for (final v in victims) v.character.id: v.currentHealth,
      };
      battle.turnEngine.resolveAbilityUse(
        attacker: holder,
        trigger: blast,
        targets: victims,
      );

      expect(victims.any((v) => v.currentHealth < before[v.character.id]!),
          isTrue,
          reason: 'the trap is out of reach, so the blast goes through');
      expect(armed(battle, 'bastian_cole', ReactiveKind.nullifyAoe), isTrue,
          reason: 'and the trap is not spent, so it can still fire later');
    });
  });
}
