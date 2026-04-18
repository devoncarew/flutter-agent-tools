import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_slipstream/src/deps/gemini.dart';

/// BeforeTool hook: validates Dart/Flutter package additions against pub.dev.
///
/// Gemini CLI variant — reads Gemini-format tool input JSON from stdin and
/// emits JSON output ({"systemMessage": "..."}).
///
/// Gemini input differs from Claude input:
///   - tool name is 'run_shell_command' / 'write_file' / 'replace'
///   - file path key is 'path' (not 'file_path')
///
/// Usage:
///   dart run bin/deps_check_gemini.dart --mode=pub-add
///   dart run bin/deps_check_gemini.dart --mode=pubspec-guard
///
/// Always exits 0 (advisory only — the agent decides whether to proceed).
void main(List<String> args) async {
  final parser =
      ArgParser()..addOption('mode', allowed: ['pub-add', 'pubspec-guard']);

  final ArgResults results;
  try {
    results = parser.parse(args);
  } on ArgParserException catch (e) {
    stderr.writeln('deps_check_gemini: ${e.message}');
    exit(0); // Fail open.
  }

  final String? mode = results['mode'] as String?;
  if (mode == null) {
    stderr.writeln(
      'deps_check_gemini: --mode is required. '
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

  final List<String> warnings;
  if (mode == 'pub-add') {
    warnings = await handlePubAddGemini(input);
  } else {
    warnings = await handlePubspecGuardGemini(input);
  }

  if (warnings.isNotEmpty) {
    stdout.writeln(jsonEncode(geminiValidationFailure(warnings)));
  }

  exit(0);
}
