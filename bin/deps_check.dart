import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_slipstream/src/deps/claude.dart';
import 'package:flutter_slipstream/src/deps/copilot.dart';
import 'package:flutter_slipstream/src/deps/gemini.dart';

/// Coding-agent hook: validates Dart/Flutter package additions against pub.dev.
///
/// Usage:
///   dart run bin/deps_check.dart --agent=claude  --mode=pub-add
///   dart run bin/deps_check.dart --agent=claude  --mode=pubspec-guard
///   dart run bin/deps_check.dart --agent=copilot --mode=pub-add
///   dart run bin/deps_check.dart --agent=copilot --mode=pubspec-guard
///   dart run bin/deps_check.dart --agent=gemini  --mode=pub-add
///   dart run bin/deps_check.dart --agent=gemini  --mode=pubspec-guard
///
/// Reads tool input JSON from stdin. Always exits 0 (warnings only — the
/// agent decides whether to proceed).
void main(List<String> args) async {
  final parser =
      ArgParser()
        ..addOption('agent', allowed: ['claude', 'copilot', 'gemini'])
        ..addOption('mode', allowed: ['pub-add', 'pubspec-guard']);

  final ArgResults results;
  try {
    results = parser.parse(args);
  } on ArgParserException catch (e) {
    stderr.writeln('deps_check: ${e.message}');
    exit(0); // Fail open.
  }

  final String? agent = results['agent'] as String?;
  if (agent == null) {
    stderr.writeln(
      'deps_check: --agent is required. '
      'Pass --agent=claude|copilot|gemini',
    );
    exit(0); // Fail open.
  }

  final String? mode = results['mode'] as String?;
  if (mode == null) {
    stderr.writeln(
      'deps_check: --mode is required. '
      'Pass --mode=pub-add|pubspec-guard',
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

  final bool pubAdd = mode == 'pub-add';

  switch (agent) {
    case 'claude':
      final warnings =
          pubAdd
              ? await handlePubAddClaude(input)
              : await handlePubspecGuardClaude(input);
      if (warnings.isNotEmpty) {
        stdout.writeln(jsonEncode(claudeValidationFailure(warnings)));
      }
    case 'copilot':
      final warnings =
          pubAdd
              ? await handlePubAddCopilot(input)
              : await handlePubspecGuardCopilot(input);
      if (warnings.isNotEmpty) {
        stdout.writeln(jsonEncode(copilotValidationFailure(warnings)));
      }
    case 'gemini':
      final warnings =
          pubAdd
              ? await handlePubAddGemini(input)
              : await handlePubspecGuardGemini(input);
      if (warnings.isNotEmpty) {
        stdout.writeln(jsonEncode(geminiValidationFailure(warnings)));
      }
  }

  // We call `exit` explicitly here in case any network calls — to pub.dev —
  // would otherwise delay exit.
  exit(0);
}
