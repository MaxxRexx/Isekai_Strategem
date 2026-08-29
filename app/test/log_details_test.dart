import 'package:battle_engine/battle_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/battle_models.dart';
import 'package:isekai_strategem/src/widgets/log_view.dart';

/// Three playtest reports about the Battle Log's details panel, and the
/// regression tests that keep them fixed.
///
/// "Sometimes clicking details does nothing. It shows Hide as if it opened
/// but does not show the details." That one was self-inflicted: the Details
/// button appeared whenever a line had *anything* to explain, and the panel
/// only rendered when the line had **rolls**. Every ability had rolls until
/// friendly ones stopped rolling, at which point War Chant and Guardian's
/// Aegis offered a button that did nothing.
///
/// "Why does critical miss say it hit?" The comparison came from the totals
/// and the verb came from the outcome, so any roll that something overruled
/// contradicted itself inside one sentence: "15 ≥ 7, so it misses".
///
/// "Instead of everything explained in one sentence, use bullet points."
void main() {
  LogDiceRoll die(int raw, int mod) => LogDiceRoll(
        rawRolls: [raw],
        kept: raw,
        mode: RollMode.normal,
        modifier: mod,
        total: raw + mod,
      );

  LogRollBreakdown roll({
    required int attack,
    required int defense,
    required bool isHit,
    bool isCriticalMiss = false,
    bool isCriticalHit = false,
    LogDamageDetail? damage,
  }) =>
      LogRollBreakdown(
        attackerRoll: die(attack, 0),
        defenderRoll: die(defense, 0),
        isHit: isHit,
        isCriticalHit: isCriticalHit,
        isCriticalMiss: isCriticalMiss,
        damage: damage?.finalDamage ?? 0,
        damageDetail: damage,
      );

  const damage = LogDamageDetail(
    diceRawRolls: [5, 2],
    diceFlatBonus: 7,
    diceTotal: 14,
    diceSides: 6,
    preCritMultiplier: 1.38,
    prevented: false,
    criticalHitApplied: false,
    criticalHitMultiplier: 1,
    criticalBonusDamage: 0,
    afterCriticalHit: 19,
    armor: 1,
    afterArmor: 18,
    statusDamageTypeMultiplier: 0.75,
    damageResistanceApplied: false,
    finalDamage: 14,
  );

  LogAction action({
    String trigger = 'Split Shot',
    List<LogRollBreakdown> rolls = const [],
    List<String> statuses = const [],
  }) =>
      LogAction(
        characterId: 'player:kaito_reyes',
        characterName: 'Kaito Reyes',
        triggerId: 'split_shot',
        triggerName: trigger,
        fatTriggered: false,
        targets: [
          LogTargetResult(
            targetId: 'opponent:vela_ashworth',
            targetName: 'Vela Ashworth',
            hits: rolls.where((r) => r.isHit).length,
            crits: 0,
            misses: rolls.where((r) => !r.isHit).length,
            damage: rolls.fold(0, (sum, r) => sum + r.damage),
            statusEffectsApplied: statuses,
            healthAfter: 100,
            died: false,
            rolls: rolls,
          ),
        ],
      );

  Future<void> pumpAndOpen(WidgetTester tester, LogAction a) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BattleLogView(
            rounds: [LogRound(roundNumber: 1, team: 'A', actions: [a])],
            teamAName: 'You',
            teamBName: 'Opponent',
            open: true,
            onToggle: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
  }

  group('the Details button always opens something', () {
    testWidgets('an ability with no rolls still explains itself',
        (tester) async {
      // The reported bug, exactly: War Chant rolls nothing and applies a
      // status, so it offered a button and drew nothing.
      await pumpAndOpen(
        tester,
        action(trigger: 'War Chant', statuses: const ['Empowered x1']),
      );

      expect(find.text('Hide'), findsOneWidget);
      expect(find.byType(RollBreakdownView), findsOneWidget,
          reason: 'the button said it opened, so something has to be open');
      expect(find.text('Status effects applied'), findsOneWidget);
      expect(find.textContaining('Empowered x1'), findsWidgets);
    });

    testWidgets('an ability with rolls still explains itself', (tester) async {
      await pumpAndOpen(
        tester,
        action(rolls: [roll(attack: 23, defense: 10, isHit: true, damage: damage)]),
      );
      expect(find.byType(RollBreakdownView), findsOneWidget);
    });

    testWidgets('a line with nothing to explain offers no button',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BattleLogView(
            rounds: [
              LogRound(roundNumber: 1, team: 'A', actions: [action()]),
            ],
            teamAName: 'You',
            teamBName: 'Opponent',
            open: true,
            onToggle: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Details'), findsNothing);
    });
  });

  group('the verdict never contradicts the numbers above it', () {
    String verdictOf(WidgetTester tester) {
      // The bullet that carries the comparison.
      for (final w in tester.widgetList<Text>(find.byType(Text))) {
        final text = w.textSpan?.toPlainText() ?? w.data ?? '';
        if (text.contains('≥') || text.contains('<')) {
          return text.replaceFirst('• ', '');
        }
      }
      return '';
    }

    testWidgets('a critical miss says what overruled the dice', (tester) async {
      await pumpAndOpen(
        tester,
        action(rolls: [
          roll(attack: 15, defense: 7, isHit: false, isCriticalMiss: true),
        ]),
      );

      final verdict = verdictOf(tester);
      expect(verdict, contains('15 ≥ 7'));
      expect(verdict, contains('would have landed'));
      expect(verdict, contains('critical miss'));
      expect(verdict, isNot(contains('so it misses')),
          reason: '"15 ≥ 7, so it misses" is the sentence this replaced');
    });

    testWidgets('an attack turned aside says so rather than reading as a hit',
        (tester) async {
      // A Decoy dodge beats the roll after the fact. The engine records it as
      // not landing now, and the panel says why the numbers did not settle it.
      await pumpAndOpen(
        tester,
        action(rolls: [roll(attack: 28, defense: 7, isHit: false)]),
      );

      final verdict = verdictOf(tester);
      expect(verdict, contains('28 ≥ 7'));
      expect(verdict, contains('turned aside'));
      expect(verdict, isNot(contains('so it misses')));
    });

    testWidgets('an ordinary hit stays one clause', (tester) async {
      await pumpAndOpen(
        tester,
        action(rolls: [roll(attack: 23, defense: 10, isHit: true, damage: damage)]),
      );

      final verdict = verdictOf(tester);
      expect(verdict, '23 ≥ 10, so it lands.');
    });

    testWidgets('an ordinary miss stays one clause', (tester) async {
      await pumpAndOpen(
        tester,
        action(rolls: [roll(attack: 8, defense: 19, isHit: false)]),
      );

      expect(verdictOf(tester), '8 < 19, so it misses.');
    });
  });

  group('the breakdown is a list of steps, not a paragraph', () {
    testWidgets('each step of the damage is its own line', (tester) async {
      await pumpAndOpen(
        tester,
        action(rolls: [roll(attack: 23, defense: 10, isHit: true, damage: damage)]),
      );

      final lines = [
        for (final w in tester.widgetList<Text>(find.byType(Text)))
          w.textSpan?.toPlainText() ?? w.data ?? '',
      ];
      final bullets = lines.where((l) => l.startsWith('• ')).toList();

      // Attack, Defense, verdict, then the five damage steps.
      expect(bullets.length, greaterThanOrEqualTo(8),
          reason: 'this was two run-on sentences');
      expect(bullets.any((l) => l.contains('Rolls 2d6')), isTrue);
      expect(bullets.any((l) => l.contains('flat +7')), isTrue);
      expect(bullets.any((l) => l.contains('Team Spirit')), isTrue);
      expect(bullets.any((l) => l.contains('Armor')), isTrue);
      expect(bullets.any((l) => l.contains('Final: 14 damage')), isTrue);
      expect(find.text('Damage'), findsOneWidget);

      // No step should be carrying more than one arithmetic move.
      for (final b in bullets) {
        expect('. '.allMatches(b).length, lessThanOrEqualTo(1), reason: b);
      }
    });
  });
}
