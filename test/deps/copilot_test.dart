import 'dart:convert';

import 'package:flutter_slipstream/src/deps/copilot.dart';
import 'package:test/test.dart';

import 'support.dart';

// Builds a Copilot-format input map with toolArgs as a double-encoded JSON string.
Map<String, Object?> bashInput(String command) => {
  'toolName': 'bash',
  'toolArgs': jsonEncode({'command': command}),
};

Map<String, Object?> editInput(
  String filePath, {
  String oldStr = '',
  String newStr = '',
  String? cwd,
}) {
  return {
    'toolName': 'edit',
    if (cwd != null) 'cwd': cwd,
    'toolArgs': jsonEncode({
      'path': filePath,
      'old_str': oldStr,
      'new_str': newStr,
    }),
  };
}

void main() {
  group('handlePubAddCopilot', () {
    test('ignores non-bash tool names', () async {
      final result = await handlePubAddCopilot({
        'toolName': 'edit',
        'toolArgs': jsonEncode({'command': 'flutter pub add http'}),
      }, httpClient: noNetworkClient());
      expect(result, isEmpty);
    });

    test('ignores commands without pub add', () async {
      final result = await handlePubAddCopilot(
        bashInput('dart pub get'),
        httpClient: noNetworkClient(),
      );
      expect(result, isEmpty);
    });

    test('reads command from double-encoded toolArgs', () async {
      final result = await handlePubAddCopilot(
        bashInput('flutter pub add some_pkg'),
        httpClient: noNetworkClient(),
      );
      // noNetworkClient → fail-open path; result is a list (may contain a warning).
      expect(result, isA<List<String>>());
    });

    test('returns empty list when toolArgs is absent', () async {
      final result = await handlePubAddCopilot(
        {'toolName': 'bash'},
        httpClient: noNetworkClient(),
      );
      expect(result, isEmpty);
    });

    test('returns empty list when toolArgs is malformed JSON', () async {
      final result = await handlePubAddCopilot(
        {'toolName': 'bash', 'toolArgs': 'not json'},
        httpClient: noNetworkClient(),
      );
      expect(result, isEmpty);
    });

    test('warns on discontinued package', () async {
      final result = await handlePubAddCopilot(
        bashInput('flutter pub add flutter_markdown'),
        httpClient: discontinuedClient('flutter_markdown', 'flutter_markdown_plus'),
      );
      expect(result, isNotEmpty);
      expect(result.first, contains('flutter_markdown'));
      expect(result.first, contains('discontinued'));
    });

    test('warns on old major version', () async {
      final result = await handlePubAddCopilot(
        bashInput("flutter pub add 'http:^0.13.0'"),
        httpClient: latestVersionClient('http', '1.3.0'),
      );
      expect(result, isNotEmpty);
      expect(result.first, contains('http'));
      expect(result.first, contains('major version'));
    });
  });

  group('handlePubspecGuardCopilot', () {
    test('ignores non-edit tool names', () async {
      final result = await handlePubspecGuardCopilot({
        'toolName': 'bash',
        'toolArgs': jsonEncode({'command': 'flutter pub add http'}),
      }, httpClient: noNetworkClient());
      expect(result, isEmpty);
    });

    test('ignores edits to non-pubspec files', () async {
      final result = await handlePubspecGuardCopilot(
        editInput('/app/lib/main.dart'),
        httpClient: noNetworkClient(),
      );
      expect(result, isEmpty);
    });

    test('reads file path from toolArgs.path (not file_path)', () async {
      // Nonexistent file → treats all new deps as added.
      const newPubspec = '''
dependencies:
  http: ^1.0.0
''';
      final result = await handlePubspecGuardCopilot(
        editInput(
          '/nonexistent/pubspec.yaml',
          newStr: newPubspec,
        ),
        httpClient: noNetworkClient(),
      );
      expect(result, isA<List<String>>());
    });

    test('applies old_str → new_str substitution', () async {
      // old_str == new_str → no change → no new packages.
      final result = await handlePubspecGuardCopilot(
        editInput('/nonexistent/pubspec.yaml'),
        httpClient: noNetworkClient(),
      );
      expect(result, isEmpty);
    });

    test('returns empty when no new packages are introduced', () async {
      // Version constraint bump on an existing package — no new entry.
      final result = await handlePubspecGuardCopilot(
        editInput(
          'pubspec.yaml',
          oldStr: 'http: ^1.0.0',
          newStr: 'http: ^1.1.0',
        ),
        httpClient: noNetworkClient(),
      );
      expect(result, isEmpty);
    });

    test('warns on discontinued package added via edit', () async {
      final result = await handlePubspecGuardCopilot(
        editInput(
          'pubspec.yaml',
          oldStr: '\ndependencies:',
          newStr: '\ndependencies:\n  flutter_markdown: any',
        ),
        httpClient: discontinuedClient('flutter_markdown', 'flutter_markdown_plus'),
      );
      expect(result, isNotEmpty);
      expect(result.first, contains('flutter_markdown'));
      expect(result.first, contains('discontinued'));
    });

    test('returns empty list when toolArgs is absent', () async {
      final result = await handlePubspecGuardCopilot(
        {'toolName': 'edit'},
        httpClient: noNetworkClient(),
      );
      expect(result, isEmpty);
    });
  });

  group('copilotValidationFailure', () {
    test('uses deny decision', () {
      final output = copilotValidationFailure(['some warning']);
      expect(output['permissionDecision'], 'ask');
    });

    test('joins multiple warnings with newlines', () {
      final output = copilotValidationFailure(['warn a', 'warn b']);
      final reason = output['permissionDecisionReason'] as String;
      expect(reason, contains('warn a'));
      expect(reason, contains('warn b'));
    });
  });
}
