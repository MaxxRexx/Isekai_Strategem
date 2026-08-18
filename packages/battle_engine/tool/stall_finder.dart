import 'package:battle_engine/battle_engine.dart';

/// Enumerates every board state in which neither side can reach the other, and
/// checks whether either side could break it with one legal step.
///
/// A "true stall" is a state that is mutually unreachable AND that neither
/// side can escape by moving one character one line. Those are the states the
/// 30-round limit would resolve by awarding the win to whoever was already
/// ahead, which is why they have to be impossible rather than merely resolved.
int screens(int targetStep, List<int> team) =>
    team.where((s) => s < targetStep).length;

typedef Band = (int, int);

const close01 = (0, 1);
const close02 = (0, 2);
const mid = (1, 3);
const long = (2, 4);

/// Whether the side holding [bands], standing in [mine], can reach anyone in
/// [theirs]. [softMin] lets a band fire below its minimum (at a penalty), so
/// only the maximum blocks.
bool canReachAnyone(
  List<int> mine,
  List<int> theirs,
  List<Band> bands, {
  required bool softMin,
}) {
  for (final a in mine) {
    for (final t in theirs) {
      final d = a + t + screens(t, theirs);
      for (final b in bands) {
        final lo = softMin ? 0 : b.$1;
        if (d >= lo && d <= b.$2) return true;
      }
    }
  }
  return false;
}

List<List<int>> allFormations() {
  final out = <List<int>>[];
  for (var a = 0; a < 3; a++) {
    for (var b = a; b < 3; b++) {
      for (var c = b; c < 3; c++) {
        out.add([a, b, c]);
      }
    }
  }
  return out;
}

/// Every formation one character-move away from [f].
List<List<int>> oneStepFrom(List<int> f) {
  final out = <List<int>>[];
  for (var i = 0; i < f.length; i++) {
    for (final delta in [-1, 1]) {
      final s = f[i] + delta;
      if (s < 0 || s > 2) continue;
      final next = List.of(f)..[i] = s;
      next.sort();
      out.add(next);
    }
  }
  return out;
}

String label(List<int> f) => f.map((s) => const ['F', 'M', 'B'][s]).join();

void survey(String name, Map<String, List<Band>> kits, {required bool softMin}) {
  final forms = allFormations();
  var mutual = 0;
  var trueStalls = 0;
  final examples = <String>[];
  var total = 0;

  for (final myKit in kits.entries) {
    for (final theirKit in kits.entries) {
      for (final mine in forms) {
        for (final theirs in forms) {
          total++;
          final iReach =
              canReachAnyone(mine, theirs, myKit.value, softMin: softMin);
          final theyReach =
              canReachAnyone(theirs, mine, theirKit.value, softMin: softMin);
          if (iReach || theyReach) continue;
          mutual++;
          // Can either side break it within two of their own steps, the
          // other side standing still? Two steps matters: one step is often
          // not enough to cross a band's minimum or maximum, but a player
          // willing to spend two turns walking always gets there.
          bool escapesIn(List<int> from, List<int> other, List<Band> bands) {
            if (canReachAnyone(from, other, bands, softMin: softMin)) {
              return true;
            }
            for (final a in oneStepFrom(from)) {
              if (canReachAnyone(a, other, bands, softMin: softMin)) return true;
              for (final b in oneStepFrom(a)) {
                if (canReachAnyone(b, other, bands, softMin: softMin)) {
                  return true;
                }
              }
            }
            return false;
          }

          final canEscape = escapesIn(mine, theirs, myKit.value) ||
              escapesIn(theirs, mine, theirKit.value);
          if (!canEscape) {
            trueStalls++;
            if (examples.length < 6) {
              examples.add('${myKit.key} at ${label(mine)} '
                  'vs ${theirKit.key} at ${label(theirs)}');
            }
          }
        }
      }
    }
  }
  print('\n$name');
  print('  board states surveyed: $total');
  print('  mutually unreachable:  $mutual');
  print('  unbreakable within two steps:   $trueStalls');
  for (final e in examples) {
    print('    e.g. $e');
  }
}

void main() {
  final kits01 = <String, List<Band>>{
    'C': [close01],
    'M': [mid],
    'L': [long],
    'CM': [close01, mid],
    'CL': [close01, long],
    'ML': [mid, long],
    'CML': [close01, mid, long],
  };
  final kits02 = <String, List<Band>>{
    'C': [close02],
    'M': [mid],
    'L': [long],
    'CM': [close02, mid],
    'CL': [close02, long],
    'ML': [mid, long],
    'CML': [close02, mid, long],
  };

  print('Every kit-versus-kit, formation-versus-formation board state, under');
  print('the screening rule. A stall needs BOTH sides unable to reach.');
  survey('Close 0-1, hard minimums (today)', kits01, softMin: false);
  survey('Close 0-2, hard minimums (as approved)', kits02, softMin: false);
  survey('Close 0-2, soft minimums', kits02, softMin: true);
  survey('Close 0-1, soft minimums', kits01, softMin: true);
}
