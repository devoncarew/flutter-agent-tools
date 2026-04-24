import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

final _scriptPath = path.join(
  Directory.current.path,
  'scripts/deps_check_copilot.sh',
);

/// Runs deps_check_copilot.sh with [stdin], returning (exitCode, stdout).
///
/// Unlike the Claude/Gemini scripts, the Copilot script takes no --mode
/// argument — it detects the mode by inspecting the JSON on stdin.
///
/// The Dart behavior is covered by unit tests; these tests focus on whether
/// the shell script correctly fast-exits (filtered) or reaches the Dart
/// invocation (pass-through).
Future<({int exitCode, String stdout})> runScript(String stdin) async {
  final process = await Process.start('bash', [_scriptPath]);
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

// Minimal Copilot-format tool-input JSON wrappers.
// Copilot sends compact JSON (no spaces after colons), so we use jsonEncode
// here to match the real wire format the shell script greps against.
// toolArgs is a double-encoded JSON string, as Copilot sends it.

String pubAddInput(String command) => jsonEncode({
  'toolName': 'bash',
  'cwd': Directory.current.absolute.path,
  'toolArgs': jsonEncode({'command': command}),
});

String editInput(String filePath, {String oldStr = '', String newStr = ''}) =>
    jsonEncode({
      'toolName': 'edit',
      'cwd': Directory.current.absolute.path,
      'toolArgs': jsonEncode({
        'path': filePath,
        'old_str': oldStr,
        'new_str': newStr,
      }),
    });

String viewInput(String filePath) => jsonEncode({
  'toolName': 'view',
  'cwd': Directory.current.absolute.path,
  'toolArgs': jsonEncode({'path': filePath}),
});

void main() {
  group('deps_check_copilot.sh (pub-add detection)', () {
    test(
      'filtered: non-pub-add bash command exits immediately with no output',
      () async {
        final r = await runScript(pubAddInput('dart pub get'));
        expect(r.exitCode, 0);
        expect(r.stdout, isEmpty);
      },
    );

    test(
      'filtered: unrecognised tool (view) exits immediately with no output',
      () async {
        final r = await runScript(viewInput('/app/pubspec.yaml'));
        expect(r.exitCode, 0);
        expect(r.stdout, isEmpty);
      },
    );

    test('pass-through: pub add command reaches Dart and exits 0', () async {
      // The Dart handler is invoked; it fails open on any issue and exits 0.
      final r = await runScript(pubAddInput('flutter pub add http'));
      expect(r.exitCode, 0);
    });

    test('warn on discontinued package', () async {
      final r = await runScript(
        pubAddInput('flutter pub add flutter_markdown'),
      );
      expect(r.exitCode, 0);
      expect(r.stdout, isNotEmpty);
      expect(r.stdout, contains('flutter_markdown'));
      expect(r.stdout, contains('discontinued'));
    });
  });

  group('deps_check_copilot.sh (pubspec-guard detection)', () {
    test(
      'filtered: edit to a non-pubspec file exits immediately with no output',
      () async {
        final r = await runScript(editInput('/app/lib/main.dart'));
        expect(r.exitCode, 0);
        expect(r.stdout, isEmpty);
      },
    );

    test(
      'pass-through: edit to pubspec.yaml reaches Dart and exits 0',
      () async {
        final r = await runScript(editInput('/app/pubspec.yaml'));
        expect(r.exitCode, 0);
      },
    );

    test('warn on discontinued package', () async {
      final r = await runScript(
        editInput(
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
}
