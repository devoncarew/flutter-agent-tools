import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

final _scriptPath = path.join(
  Directory.current.path,
  'scripts/deps_check.js',
);

/// Runs deps_check.js with [args] and [stdin], returning (exitCode, stdout).
///
/// Tests focus on whether the script correctly fast-exits (filtered) or
/// invokes Dart (pass-through). Dart-level validation logic is covered by
/// unit tests in test/deps/.
Future<({int exitCode, String stdout})> runScript(
  List<String> args,
  String stdin,
) async {
  final process = await Process.start('node', [_scriptPath, ...args]);
  try {
    process.stdin.write(stdin);
    await process.stdin.close();
  } catch (_) {
    // The script may exit before reading stdin (fast-exit path); ignore.
  }

  final out = await process.stdout.transform(utf8.decoder).join();
  await process.stderr.drain<void>();
  final exitCode = await process.exitCode;

  return (exitCode: exitCode, stdout: out);
}

// --- Claude-format input builders ---

String claudePubAddInput(String command) => jsonEncode({
  'tool_name': 'Bash',
  'tool_input': {'command': command},
});

String claudeEditInput(
  String filePath, {
  String oldString = '',
  String newString = '',
}) => jsonEncode({
  'tool_name': 'Edit',
  'tool_input': {
    'file_path': filePath,
    'old_string': oldString,
    'new_string': newString,
  },
});

// --- Copilot-format input builders ---
// toolArgs is a double-encoded JSON string, as Copilot sends it.

String copilotPubAddInput(String command) => jsonEncode({
  'toolName': 'bash',
  'cwd': Directory.current.absolute.path,
  'toolArgs': jsonEncode({'command': command}),
});

String copilotEditInput(
  String filePath, {
  String oldStr = '',
  String newStr = '',
}) => jsonEncode({
  'toolName': 'edit',
  'cwd': Directory.current.absolute.path,
  'toolArgs': jsonEncode({
    'path': filePath,
    'old_str': oldStr,
    'new_str': newStr,
  }),
});

String copilotViewInput(String filePath) => jsonEncode({
  'toolName': 'view',
  'cwd': Directory.current.absolute.path,
  'toolArgs': jsonEncode({'path': filePath}),
});

// --- Gemini-format input builders ---

String geminiPubAddInput(String command) => jsonEncode({
  'tool_name': 'run_shell_command',
  'tool_input': {'command': command},
});

String geminiWriteFileInput(String filePath, {String content = ''}) => jsonEncode({
  'tool_name': 'write_file',
  'cwd': Directory.current.absolute.path,
  'tool_input': {'file_path': filePath, 'content': content},
});

void main() {
  // -------------------------------------------------------------------------
  // Claude
  // -------------------------------------------------------------------------

  group('deps_check.js --agent=claude --mode=pub-add', () {
    test('filtered: non-pub-add command exits with no output', () async {
      final r = await runScript(
        ['--agent=claude', '--mode=pub-add'],
        claudePubAddInput('dart pub get'),
      );
      expect(r.exitCode, 0);
      expect(r.stdout, isEmpty);
    });

    test('pass-through: pub add command reaches Dart and exits 0', () async {
      final r = await runScript(
        ['--agent=claude', '--mode=pub-add'],
        claudePubAddInput('flutter pub add http'),
      );
      expect(r.exitCode, 0);
    });

    test('warn on discontinued package', () async {
      final r = await runScript(
        ['--agent=claude', '--mode=pub-add'],
        claudePubAddInput('flutter pub add flutter_markdown'),
      );
      expect(r.exitCode, 0);
      expect(r.stdout, isNotEmpty);
      expect(r.stdout, contains('flutter_markdown'));
      expect(r.stdout, contains('discontinued'));
    });
  });

  group('deps_check.js --agent=claude --mode=pubspec-guard', () {
    test('filtered: edit to non-pubspec file exits with no output', () async {
      final r = await runScript(
        ['--agent=claude', '--mode=pubspec-guard'],
        claudeEditInput('/app/lib/main.dart'),
      );
      expect(r.exitCode, 0);
      expect(r.stdout, isEmpty);
    });

    test('pass-through: edit to pubspec.yaml reaches Dart and exits 0', () async {
      final r = await runScript(
        ['--agent=claude', '--mode=pubspec-guard'],
        claudeEditInput('/app/pubspec.yaml'),
      );
      expect(r.exitCode, 0);
    });

    test('warn on discontinued package', () async {
      final r = await runScript(
        ['--agent=claude', '--mode=pubspec-guard'],
        claudeEditInput(
          'pubspec.yaml',
          oldString: '\ndependencies:',
          newString: '\ndependencies:\n  flutter_markdown: any',
        ),
      );
      expect(r.exitCode, 0);
      expect(r.stdout, isNotEmpty);
      expect(r.stdout, contains('flutter_markdown'));
      expect(r.stdout, contains('discontinued'));
    });
  });

  // -------------------------------------------------------------------------
  // Copilot
  // -------------------------------------------------------------------------

  group('deps_check.js --agent=copilot (pub-add detection)', () {
    test('filtered: non-pub-add bash command exits with no output', () async {
      final r = await runScript(
        ['--agent=copilot'],
        copilotPubAddInput('dart pub get'),
      );
      expect(r.exitCode, 0);
      expect(r.stdout, isEmpty);
    });

    test('filtered: unrecognised tool exits with no output', () async {
      final r = await runScript(
        ['--agent=copilot'],
        copilotViewInput('/app/pubspec.yaml'),
      );
      expect(r.exitCode, 0);
      expect(r.stdout, isEmpty);
    });

    test('pass-through: pub add command reaches Dart and exits 0', () async {
      final r = await runScript(
        ['--agent=copilot'],
        copilotPubAddInput('flutter pub add http'),
      );
      expect(r.exitCode, 0);
    });

    test('warn on discontinued package', () async {
      final r = await runScript(
        ['--agent=copilot'],
        copilotPubAddInput('flutter pub add flutter_markdown'),
      );
      expect(r.exitCode, 0);
      expect(r.stdout, isNotEmpty);
      expect(r.stdout, contains('flutter_markdown'));
      expect(r.stdout, contains('discontinued'));
    });
  });

  group('deps_check.js --agent=copilot (pubspec-guard detection)', () {
    test('filtered: edit to non-pubspec file exits with no output', () async {
      final r = await runScript(
        ['--agent=copilot'],
        copilotEditInput('/app/lib/main.dart'),
      );
      expect(r.exitCode, 0);
      expect(r.stdout, isEmpty);
    });

    test('pass-through: edit to pubspec.yaml reaches Dart and exits 0', () async {
      final r = await runScript(
        ['--agent=copilot'],
        copilotEditInput('/app/pubspec.yaml'),
      );
      expect(r.exitCode, 0);
    });

    test('warn on discontinued package', () async {
      final r = await runScript(
        ['--agent=copilot'],
        copilotEditInput(
          'pubspec.yaml',
          oldStr: '\ndependencies:',
          newStr: '\ndependencies:\n  flutter_markdown: any',
        ),
      );
      expect(r.exitCode, 0);
      expect(r.stdout, isNotEmpty);
      expect(r.stdout, contains('flutter_markdown'));
      expect(r.stdout, contains('discontinued'));
    });
  });

  // -------------------------------------------------------------------------
  // Gemini
  // -------------------------------------------------------------------------

  group('deps_check.js --agent=gemini --mode=pub-add', () {
    test('filtered: non-pub-add shell command exits with no output', () async {
      final r = await runScript(
        ['--agent=gemini', '--mode=pub-add'],
        geminiPubAddInput('dart pub get'),
      );
      expect(r.exitCode, 0);
      expect(r.stdout, isEmpty);
    });

    test('pass-through: pub add command reaches Dart and exits 0', () async {
      final r = await runScript(
        ['--agent=gemini', '--mode=pub-add'],
        geminiPubAddInput('flutter pub add http'),
      );
      expect(r.exitCode, 0);
    });

    test('warn on discontinued package', () async {
      final r = await runScript(
        ['--agent=gemini', '--mode=pub-add'],
        geminiPubAddInput('flutter pub add flutter_markdown'),
      );
      expect(r.exitCode, 0);
      expect(r.stdout, isNotEmpty);
      expect(r.stdout, contains('flutter_markdown'));
      expect(r.stdout, contains('discontinued'));
    });
  });

  group('deps_check.js --agent=gemini --mode=pubspec-guard', () {
    test('filtered: write to non-pubspec file exits with no output', () async {
      final r = await runScript(
        ['--agent=gemini', '--mode=pubspec-guard'],
        geminiWriteFileInput('/app/lib/main.dart'),
      );
      expect(r.exitCode, 0);
      expect(r.stdout, isEmpty);
    });

    test('pass-through: write to pubspec.yaml reaches Dart and exits 0', () async {
      final r = await runScript(
        ['--agent=gemini', '--mode=pubspec-guard'],
        geminiWriteFileInput('/app/pubspec.yaml'),
      );
      expect(r.exitCode, 0);
    });

    test('warn on discontinued package', () async {
      var content = File('pubspec.yaml').readAsStringSync();
      content = content.replaceFirst(
        '\ndependencies:',
        '\ndependencies:\n  flutter_markdown: any',
      );
      final r = await runScript(
        ['--agent=gemini', '--mode=pubspec-guard'],
        geminiWriteFileInput('pubspec.yaml', content: content),
      );
      expect(r.exitCode, 0);
      expect(r.stdout, isNotEmpty);
      expect(r.stdout, contains('flutter_markdown'));
      expect(r.stdout, contains('discontinued'));
    });
  });
}
