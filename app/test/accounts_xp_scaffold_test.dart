import 'package:battle_engine/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isekai_strategem/src/game/account.dart';
import 'package:isekai_strategem/src/game/team_efficiency.dart';
import 'package:isekai_strategem/src/game/xp_ledger.dart';

/// Combat-v2 section 15 accounts/XP CLIENT SCAFFOLD: the local stubs behave so
/// the game runs before a real backend exists.
void main() {
  group('LocalStubAccountService (stress-free onboarding)', () {
    test('guest entry needs no sign-up and is marked a guest', () async {
      final svc = LocalStubAccountService();
      final r = await svc.continueAsGuest();
      expect(r.ok, isTrue);
      expect(svc.current!.isGuest, isTrue);
      svc.dispose();
    });

    test('linking a guest keeps the same id (no lost progress)', () async {
      final svc = LocalStubAccountService();
      await svc.continueAsGuest();
      final guestId = svc.current!.id;

      final linked = await svc.linkGuest(AuthMethod.google, email: 'a@b.com');
      expect(linked.ok, isTrue);
      expect(svc.current!.id, guestId, reason: 'id preserved across upgrade');
      expect(svc.current!.isGuest, isFalse);
      expect(svc.current!.method, AuthMethod.google);
      svc.dispose();
    });

    test('social sign-in and sign-out flow', () async {
      final svc = LocalStubAccountService();
      expect((await svc.signInWithGoogle()).ok, isTrue);
      expect(svc.current!.method, AuthMethod.google);
      await svc.signOut();
      expect(svc.current, isNull);
      svc.dispose();
    });

    test('email link rejects an obviously invalid address', () async {
      final svc = LocalStubAccountService();
      expect((await svc.signInWithEmailLink('not-an-email')).ok, isFalse);
      expect((await svc.signInWithEmailLink('me@here.com')).ok, isTrue);
      svc.dispose();
    });

    test('onboarding surfaces guest first, then social, then email', () {
      expect(kOnboardingMethods.first, AuthMethod.guest);
      expect(kOnboardingMethods, contains(AuthMethod.google));
      expect(kOnboardingMethods, contains(AuthMethod.email));
    });
  });

  group('LocalStubXpLedger (inverse-TEG award)', () {
    test('applies the inverse-TEG multiplier and accumulates', () async {
      final ledger = LocalStubXpLedger();
      final award = await ledger.recordBattleResult(BattleResultReport(
        playerId: 'p1',
        baseXp: 100,
        tier: TegTier.d,
        won: true,
        endedAt: DateTime(2026),
      ));
      expect(award.awardedXp, 175); // D = +75%
      expect(award.totalXp, 175);
      expect(await ledger.currentXp('p1'), 175);

      final second = await ledger.recordBattleResult(BattleResultReport(
        playerId: 'p1',
        baseXp: 100,
        tier: TegTier.sss,
        won: false,
        endedAt: DateTime(2026),
      ));
      expect(second.awardedXp, 105); // SSS = +5%
      expect(second.totalXp, 280);
    });

    test('fromOutcome maps win/loss to the controlled side', () {
      final asA = BattleResultReport.fromOutcome(
        playerId: 'p1',
        baseXp: 100,
        tier: TegTier.b,
        outcome: BattleOutcome.teamAWins,
        playerIsTeamA: true,
      );
      expect(asA.won, isTrue);

      final asB = BattleResultReport.fromOutcome(
        playerId: 'p1',
        baseXp: 100,
        tier: TegTier.b,
        outcome: BattleOutcome.teamAWins,
        playerIsTeamA: false,
      );
      expect(asB.won, isFalse);
    });
  });
}
