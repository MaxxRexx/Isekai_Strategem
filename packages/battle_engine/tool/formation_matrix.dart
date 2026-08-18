/// Formation against formation under the screening rule (RPP), to answer
/// whether one line-up dominates.
///
/// Score is the number of (my character, their character, band) combinations
/// that can reach, which is a proxy for how much of a mixed squad's kit is
/// live. Net is my reach minus theirs, so positive means the row formation is
/// favoured against the column formation.
int screens(int targetStep, List<int> theirSteps) =>
    theirSteps.where((s) => s < targetStep).length;

const bands = <String, (int, int)>{
  'Close': (0, 2), // widened, as approved
  'Mid': (1, 3),
  'Long': (2, 4),
};

int reachScore(List<int> mine, List<int> theirs) {
  var n = 0;
  for (final a in mine) {
    for (final t in theirs) {
      final d = a + t + screens(t, theirs);
      for (final b in bands.values) {
        if (d >= b.$1 && d <= b.$2) n++;
      }
    }
  }
  return n;
}

/// All ten ways three characters can occupy three lines.
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

String label(List<int> f) =>
    f.map((s) => const ['F', 'M', 'B'][s]).join();

void main(List<String> args) {
  if (args.contains('--kits')) {
    kits();
    return;
  }
  final forms = allFormations();

  print('NET REACH: row formation minus column formation.');
  print('Positive means the row out-reaches the column.\n');
  print('        ${forms.map((f) => label(f).padLeft(6)).join()}   avg');
  for (final mine in forms) {
    final nets = <int>[];
    final row = forms.map((theirs) {
      final net = reachScore(mine, theirs) - reachScore(theirs, mine);
      nets.add(net);
      return '${net > 0 ? '+' : ''}$net'.padLeft(6);
    }).join();
    final avg = nets.reduce((a, b) => a + b) / nets.length;
    print('  ${label(mine).padRight(6)}$row  ${avg.toStringAsFixed(1).padLeft(6)}');
  }

  print('\n\nHOW EXPOSED IS EACH OF MY CHARACTERS, by formation.');
  print('Bands that can reach them, summed over the three lines an enemy');
  print('could be standing on (max 9 per character).\n');
  for (final mine in forms) {
    final per = <String>[];
    for (final a in mine) {
      var n = 0;
      for (final enemyLine in [0, 1, 2]) {
        final d = enemyLine + a + screens(a, mine);
        for (final b in bands.values) {
          if (d >= b.$1 && d <= b.$2) n++;
        }
      }
      per.add('${const ['F', 'M', 'B'][a]}:$n');
    }
    final total = mine.fold<int>(0, (sum, a) {
      var n = 0;
      for (final enemyLine in [0, 1, 2]) {
        final d = enemyLine + a + screens(a, mine);
        for (final b in bands.values) {
          if (d >= b.$1 && d <= b.$2) n++;
        }
      }
      return sum + n;
    });
    print('  ${label(mine).padRight(6)} ${per.join('  ').padRight(22)} '
        'squad total $total');
  }

  print('\n\nTHE UNSCREENED SNIPER: where is safe once the screen is gone?');
  print('One character alone, against an enemy on each of their lines.\n');
  print('  I stand at   from their F   from their M   from their B');
  for (final mine in [0, 1, 2]) {
    final cells = [0, 1, 2].map((enemyLine) {
      final d = enemyLine + mine;
      final hit = bands.entries
          .where((e) => d >= e.value.$1 && d <= e.value.$2)
          .map((e) => e.key)
          .toList();
      return '${hit.isEmpty ? 'safe' : hit.join('/')} (d$d)'.padRight(15);
    }).join();
    print('  ${const ['Front ', 'Middle', 'Back  '][mine]}       $cells');
  }
}

/// Archetype viability: can a squad built entirely of one band still find a
/// formation that works against every enemy formation? Run with `--kits`.
void kits() {
  final forms = allFormations();
  const kitBands = {
    'all Close': [(0, 2), (0, 2), (0, 2)],
    'all Mid': [(1, 3), (1, 3), (1, 3)],
    'all Long': [(2, 4), (2, 4), (2, 4)],
    'mixed C/M/L': [(0, 2), (1, 3), (2, 4)],
  };

  print('\n\nARCHETYPE VIABILITY');
  print('For each kit: its best formation against each enemy formation, and');
  print('how many of its 3 characters can reach at least one enemy there.\n');
  for (final kit in kitBands.entries) {
    print('  ${kit.key}');
    var worst = 3;
    for (final theirs in forms) {
      var bestReach = 0;
      var bestForm = '';
      for (final mine in forms) {
        var reaching = 0;
        for (var i = 0; i < 3; i++) {
          final a = mine[i];
          final band = kit.value[i];
          final canHit = theirs.any((t) {
            final d = a + t + screens(t, theirs);
            return d >= band.$1 && d <= band.$2;
          });
          if (canHit) reaching++;
        }
        if (reaching > bestReach) {
          bestReach = reaching;
          bestForm = label(mine);
        }
      }
      if (bestReach < worst) worst = bestReach;
      print('    vs ${label(theirs)}: best ${bestForm.padRight(4)} '
          '$bestReach of 3 can act');
    }
    print('    worst case across all enemy formations: $worst of 3\n');
  }
}
