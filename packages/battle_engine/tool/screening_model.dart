import 'package:battle_engine/battle_engine.dart';

/// Models the proposed screening rule against the current one.
///
/// Proposed: effective distance = my step + their step + the number of living
/// enemies standing on a line strictly in front of the target, on the target's
/// own side. Bands unchanged except Close widening to 0-2 in the variant.
int step(BattlePosition p) => p.step;

int screens(BattlePosition target, List<BattlePosition> theirTeam) =>
    theirTeam.where((p) => p.step < target.step).length;

int effective(
  BattlePosition me,
  BattlePosition target,
  List<BattlePosition> theirTeam,
) =>
    step(me) + step(target) + screens(target, theirTeam);

const bands = {
  'Close': (0, 1),
  'Close+': (0, 2), // the widened variant
  'Mid': (1, 3),
  'Long': (2, 4),
};

String reachFrom(
  BattlePosition target,
  List<BattlePosition> theirTeam,
  String band,
) {
  final (lo, hi) = bands[band]!;
  final from = <String>[];
  for (final me in BattlePosition.values) {
    final d = effective(me, target, theirTeam);
    if (d >= lo && d <= hi) from.add('${me.label[0]}$d');
  }
  return from.isEmpty ? '-- none --' : from.join(' ');
}

void formation(String name, List<BattlePosition> theirTeam) {
  print('\n$name');
  print('  their line-up: ${theirTeam.map((p) => p.label).join(', ')}');
  const header = '    target        screens   Close(0-1)   Close+(0-2)'
      '   Mid(1-3)     Long(2-4)';
  print(header);
  final seen = <BattlePosition>{};
  for (final target in theirTeam) {
    if (!seen.add(target)) continue;
    final s = screens(target, theirTeam);
    print('    ${target.label.padRight(14)}$s'.padRight(26) +
        reachFrom(target, theirTeam, 'Close').padRight(13) +
        reachFrom(target, theirTeam, 'Close+').padRight(15) +
        reachFrom(target, theirTeam, 'Mid').padRight(13) +
        reachFrom(target, theirTeam, 'Long'));
  }
}

void main() {
  print('Reachable from which of MY lines, and at what effective distance.');
  print('F/M/B = I stand on my front / middle / back line.');

  formation('THE CAMP: all three at the back',
      [BattlePosition.back, BattlePosition.back, BattlePosition.back]);
  formation('THE SCREEN: two at the front, sniper at the back',
      [BattlePosition.front, BattlePosition.front, BattlePosition.back]);
  formation('THE SCREEN, one screen dead',
      [BattlePosition.front, BattlePosition.back]);
  formation('THE SCREEN, both screens dead', [BattlePosition.back]);
  formation('SPREAD: one on each line',
      [BattlePosition.front, BattlePosition.middle, BattlePosition.back]);
  formation('THE RUSH: all three at the front',
      [BattlePosition.front, BattlePosition.front, BattlePosition.front]);

  // How many of the real catalogue's offensive Triggers reach a screened
  // sniper, under each rule.
  final offensive = TriggerCatalog.defaultCatalog.all
      .whereType<ActiveTrigger>()
      .where((t) => t.targetAffiliation == TargetAffiliation.opponent)
      .toList();
  final screened = [
    BattlePosition.front,
    BattlePosition.front,
    BattlePosition.back
  ];
  print('\n\nAgainst the screened sniper, of ${offensive.length} offensive '
      'Triggers, how many can reach from my best line:');
  for (final widen in [false, true]) {
    var best = 0;
    BattlePosition? bestLine;
    for (final me in BattlePosition.values) {
      final d = effective(me, BattlePosition.back, screened);
      final n = offensive.where((t) {
        final lo = widen && t.rangeTag == RangeTag.close
            ? 0
            : t.rangeTag.minDistance;
        final hi = widen && t.rangeTag == RangeTag.close
            ? 2
            : t.rangeTag.maxDistance;
        return d >= lo && d <= hi;
      }).length;
      if (n > best) {
        best = n;
        bestLine = me;
      }
    }
    print('  Close ${widen ? 'widened to 0-2' : 'as now, 0-1'}: '
        '$best Triggers, from my ${bestLine?.label ?? 'nowhere'}');
  }
}
