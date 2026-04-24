import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_slipstream/src/deps/copilot.dart';

/// GitHub Copilot preToolUse hook: validates Dart/Flutter package additions
/// against pub.dev.
///
/// Copilot input differs from Claude/Gemini input:
///   - camelCase field names: toolName, toolArgs, cwd
///   - toolArgs is a double-encoded JSON string, not a nested object
///   - tool names are lowercase: 'bash', 'edit'
///   - edit args use 'path', 'old_str', 'new_str'
///
/// Usage:
///   dart run bin/deps_check_copilot.dart --mode=pub-add
///   dart run bin/deps_check_copilot.dart --mode=pubspec-guard
///
/// Always exits 0 (advisory only — the agent decides whether to proceed).
void main(List<String> args) async {
  final parser =
      ArgParser()..addOption('mode', allowed: ['pub-add', 'pubspec-guard']);

  final ArgResults results;
  try {
    results = parser.parse(args);
  } on ArgParserException catch (e) {
    stderr.writeln('deps_check_copilot: ${e.message}');
    exit(0); // Fail open.
  }

  final String? mode = results['mode'] as String?;
  if (mode == null) {
    stderr.writeln(
      'deps_check_copilot: --mode is required. '
      'Pass --mode=pub-add or --mode=pubspec-guard',
    );
    exit(0); // Fail open.
  }

  final String rawInput;
  try {
    rawInput = await stdin.transform(utf8.decoder).join();
  } catch (_) {
    exit(0);
  }

  final Map<String, Object?> input;
  try {
    input = (jsonDecode(rawInput) as Map).cast<String, Object?>();
  } catch (_) {
    exit(0);
  }

  final warnings =
      mode == 'pub-add'
          ? await handlePubAddCopilot(input)
          : await handlePubspecGuardCopilot(input);

  if (warnings.isNotEmpty) {
    stdout.writeln(jsonEncode(copilotValidationFailure(warnings)));
  }

  exit(0);
}
