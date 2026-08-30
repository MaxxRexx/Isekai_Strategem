import 'dart:io';

import 'package:test/test.dart';

/// Enforces the working agreement's absolute rule: no em dash (U+2014)
/// anywhere in the documents or the source. A rule written only in prose is
/// only as good as whoever remembers it, so this fails the moment one lands in
/// a tracked `.md` or `.dart` file. It cannot police chat replies or commit
/// messages, which is the half that stays on the author.
///
/// The character is built from its code unit here, never written literally, so
/// this guard does not trip on itself.
void main() {
  final emDash = String.fromCharCode(0x2014);

  // The only two files where the character legitimately appears, both *about*
  // forbidding it: CLAUDE.md states the rule, and the app suite's
  // describe_trigger_test asserts a description never contains one. Everything
  // else is fair game for the check.
  final allow = <String>{
    'CLAUDE.md',
    'app/test/describe_trigger_test.dart',
  };

  test('no em dash in any tracked .md or .dart file', () {
    final root = _repoRoot();
    final rootLen = root.path.length + 1;
    final offenders = <String>[];

    for (final file in _sourceAndDocs(root)) {
      final rel = file.path.substring(rootLen).replaceAll('\\', '/');
      if (allow.contains(rel)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains(emDash)) {
          offenders.add('$rel:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'The em dash (U+2014) is banned by the working agreement. '
          'Use a period, comma, parentheses or a plain hyphen instead. '
          'Found in:\n${offenders.join('\n')}',
    );
  });
}

/// The repository root, found by walking up from the current directory to the
/// first folder holding `CLAUDE.md`, so the check runs the same whether it is
/// launched from the package or the repo root.
Directory _repoRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    if (File('${dir.path}/CLAUDE.md').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
          'Could not find the repo root (no CLAUDE.md above ${Directory.current.path}).');
    }
    dir = parent;
  }
}

/// Every `.md` and `.dart` file under [root], skipping build output, tooling
/// caches and version-control internals rather than descending into them.
Iterable<File> _sourceAndDocs(Directory root) sync* {
  const skipDirs = {
    '.git',
    '.dart_tool',
    'build',
    '.gradle',
    'node_modules',
    'Pods',
  };
  final stack = <Directory>[root];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    for (final entity in entries) {
      if (entity is Directory) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (!skipDirs.contains(name)) stack.add(entity);
      } else if (entity is File &&
          (entity.path.endsWith('.md') || entity.path.endsWith('.dart'))) {
        yield entity;
      }
    }
  }
}
