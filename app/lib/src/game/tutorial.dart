import 'draft.dart';

/// One scripted squad-setup step: which slot to fill with which character.
class TutorialSetupStep {
  final int slot;
  final String charId;
  final String text;
  const TutorialSetupStep(this.slot, this.charId, this.text);
}

/// One scripted battle step: either "use this exact trigger with this
/// character" or the FAT demonstration ("use [minUses]+ abilities").
class TutorialBattleStep {
  final String characterId;
  final String? triggerId; // null for the FAT step
  final int minUses;
  final String text;
  const TutorialBattleStep(this.characterId, this.triggerId, this.text)
    : minUses = 1;
  const TutorialBattleStep.fat(this.characterId, this.minUses, this.text)
    : triggerId = null;
  bool get isFatStep => triggerId == null;
}

const tutorialOpponentIds = ['yuki_amaral', 'celestine_moreau', 'haru_ellison'];
const tutorialOpponentProfileId = 'the_turtle';

/// The exact Loadout each scripted squad member must draft.
const tutorialLoadouts =
    <String, ({List<String> triggerIds, String? blackTriggerId})>{
      'ren_kobayashi': (
        triggerIds: [
          'twin_fang_strike',
          'cleave',
          'piercing_thrust',
          'whirlwind_slash',
        ],
        blackTriggerId: null,
      ),
      'ilona_vance': (
        triggerIds: ['shatterpoint', 'binding_snare', 'fortify', 'second_wind'],
        blackTriggerId: 'bastion_frame',
      ),
      'priya_nakamura': (
        triggerIds: [
          'soul_siphon',
          'second_wind',
          'rally_cry',
          'cleansing_ward',
        ],
        blackTriggerId: null,
      ),
    };

const tutorialSetupSteps = [
  TutorialSetupStep(
    0,
    'ren_kobayashi',
    "Let's play through one full battle turn together. First, select Ren Kobayashi for Agent I, your Attacker.",
  ),
  TutorialSetupStep(
    1,
    'ilona_vance',
    'Good. Now select Ilona Vance for Agent II, your Defender.',
  ),
  TutorialSetupStep(
    2,
    'priya_nakamura',
    'Last one: select Priya Nakamura for Agent III, your Support.',
  ),
];

const tutorialBattleSteps = [
  TutorialBattleStep(
    'ren_kobayashi',
    'twin_fang_strike',
    'Use Twin Fang Strike with Ren Kobayashi against one of the opponents.',
  ),
  TutorialBattleStep(
    'ilona_vance',
    'fortify',
    'Now use Fortify with Ilona Vance. It targets herself, so just confirm the ability.',
  ),
  TutorialBattleStep(
    'priya_nakamura',
    'rally_cry',
    'Finally, use Rally Cry with Priya Nakamura on one of your allies.',
  ),
  TutorialBattleStep.fat(
    'ren_kobayashi',
    2,
    'Full Arms Trigger (FAT) just triggered for Ren Kobayashi! Normally each character gets 1 ability use per turn, but a FAT trigger allows up to 3 in the same turn instead. Chaining 2 or more does carry a real cost afterward (doubled cooldowns and halved Trion Affinity next turn), but it is worth it for the burst.',
  ),
];

enum TutorialPhase { setup, loadout, battle, done }

/// The Guided Tutorial's live state, layered over the normal Play flow:
/// at every step, everything except the single scripted action is locked
/// by the UI, so "wait for the action to complete" is enforced up front
/// rather than validated after the fact.
class TutorialState {
  TutorialPhase phase = TutorialPhase.setup;
  int setupStepIndex = 0;
  // Each of the 3 characters gets an entire team turn to itself (the
  // shared Trion Pool's forced-Low first-turn income only covers one
  // 10-Trion ability, not three), so the script waits for an explicit
  // End Turn between each scripted ability use.
  int battleStepIndex = 0;
  bool awaitingEndTurn = false;
  // Round 4 demonstrates FAT, forced (rather than left to the real
  // probabilistic roll) so the walkthrough is deterministic.
  bool fatForced = false;
  int fatUsesThisRound = 0;

  TutorialSetupStep? get currentSetupStep =>
      phase == TutorialPhase.setup && setupStepIndex < tutorialSetupSteps.length
      ? tutorialSetupSteps[setupStepIndex]
      : null;

  TutorialBattleStep? get currentBattleStep =>
      phase == TutorialPhase.battle &&
          !awaitingEndTurn &&
          battleStepIndex < tutorialBattleSteps.length
      ? tutorialBattleSteps[battleStepIndex]
      : null;

  bool get battleScriptFinished =>
      battleStepIndex >= tutorialBattleSteps.length && !awaitingEndTurn;

  String bannerText({List<String>? teamAIds, int? currentLoadoutIndex}) {
    switch (phase) {
      case TutorialPhase.setup:
        return currentSetupStep?.text ??
            'Your squad is set. Tap "Next: Build Loadouts" to continue.';
      case TutorialPhase.loadout:
        final charId = teamAIds![currentLoadoutIndex!];
        final script = tutorialLoadouts[charId]!;
        final triggerNames = script.triggerIds
            .map((id) => triggerCatalog[id].name)
            .join(', ');
        var text =
            'Build ${roster[charId].name}\'s Loadout: check '
            '$triggerNames.';
        if (script.blackTriggerId != null) {
          text +=
              ' Then select the ${blackTriggerCatalog[script.blackTriggerId!].name} Black Trigger below.';
        }
        return '$text Tap "Confirm Loadout" once everything is checked.';
      case TutorialPhase.battle:
        if (awaitingEndTurn) {
          return 'Tap "End Turn" to pass control to your opponent, then we will continue with the next character.';
        }
        final step = currentBattleStep;
        if (step == null) {
          return 'Nicely done. Continue playing freely, or explore Simulate mode.';
        }
        if (step.isFatStep) {
          final remaining = step.minUses - fatUsesThisRound;
          return step.text +
              (remaining > 0
                  ? ' Use $remaining more ${remaining == 1 ? 'ability' : 'abilities'} with Ren this turn.'
                  : '');
        }
        return step.text;
      case TutorialPhase.done:
        return 'Nicely done. Continue playing freely, or explore Simulate mode.';
    }
  }

  void onSetupPick(int slot, String charId) {
    final step = currentSetupStep;
    if (step == null || step.slot != slot || step.charId != charId) return;
    setupStepIndex++;
  }

  /// Called after the player uses an ability; advances the battle script.
  void onAbilityUsed(String characterId, String triggerId) {
    if (phase != TutorialPhase.battle || awaitingEndTurn) return;
    final step = currentBattleStep;
    if (step == null || step.characterId != characterId) return;
    if (step.isFatStep) {
      fatUsesThisRound++;
      if (fatUsesThisRound >= step.minUses) awaitingEndTurn = true;
      return;
    }
    if (step.triggerId != triggerId) return;
    awaitingEndTurn = true;
  }

  void onEndTurn() {
    if (awaitingEndTurn) {
      awaitingEndTurn = false;
      battleStepIndex++;
    }
  }
}
