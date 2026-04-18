import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

final _scriptPath = path.join(
  Directory.current.path,
  'scripts/deps_check_gemini.sh',
);

/// Runs deps_check_gemini.sh with [mode] and [stdin], returning
/// (exitCode, stdout).
///
/// The Dart behavior is covered by unit tests; these tests focus on whether
/// the shell script correctly fast-exits (filtered) or reaches the Dart
/// invocation (pass-through).
Future<({int exitCode, String stdout})> runScript(
  String mode,
  String stdin,
) async {
  final process = await Process.start('bash', [_scriptPath, '--mode=$mode']);
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

// Minimal Gemini-format tool-arguments JSON wrappers.
String pubAddInput(String command) => jsonEncode({
  'tool_name': 'run_shell_command',
  'tool_input': {'command': command},
});

String writeFileInput(String filePath, {String content = ''}) => jsonEncode({
  'tool_name': 'write_file',
  'tool_input': {'path': filePath, 'content': content},
});

void main() {
  group('deps_check_gemini.sh --mode=pub-add', () {
    test(
      'filtered: non-pub-add shell command exits immediately with no output',
      () async {
        final r = await runScript('pub-add', pubAddInput('dart pub get'));
        expect(r.exitCode, 0);
        expect(r.stdout, isEmpty);
      },
    );

    test('pass-through: pub add command reaches Dart and exits 0', () async {
      // The Dart handler is invoked; it fails open on any issue and exits 0.
      final r = await runScript('pub-add', pubAddInput('flutter pub add http'));
      expect(r.exitCode, 0);
    });

    // Note that this does actual network access.
    test('warn on discontinued package', () async {
      final r = await runScript(
        'pub-add',
        pubAddInput('flutter pub add flutter_markdown'),
      );
      expect(r.exitCode, 0);
      expect(r.stdout, isNotEmpty);
      expect(r.stdout, contains('flutter_markdown'));
      expect(r.stdout, contains('discontinued'));
    });
  });

  group('deps_check_gemini.sh --mode=pubspec-guard', () {
    test(
      'filtered: write to a non-pubspec file exits immediately with no output',
      () async {
        final r = await runScript(
          'pubspec-guard',
          writeFileInput('/app/lib/main.dart'),
        );
        expect(r.exitCode, 0);
        expect(r.stdout, isEmpty);
      },
    );

    test(
      'pass-through: write to pubspec.yaml reaches Dart and exits 0',
      () async {
        final r = await runScript(
          'pubspec-guard',
          writeFileInput('/app/pubspec.yaml'),
        );
        expect(r.exitCode, 0);
      },
    );

    // Note that this does actual network access.
    test('warn on discontinued package', () async {
      final file = File('pubspec.yaml');
      var content = file.readAsStringSync();
      content = content.replaceFirst(
        '\ndependencies:',
        '\ndependencies:\n  flutter_markdown: any',
      );

      final r = await runScript(
        'pubspec-guard',
        writeFileInput('pubspec.yaml', content: content),
      );
      expect(r.stdout, isNotEmpty);
      expect(r.stdout, contains('flutter_markdown'));
      expect(r.stdout, contains('discontinued'));
    });
  });
}
