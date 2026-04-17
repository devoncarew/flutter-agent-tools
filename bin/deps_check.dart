import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_slipstream/src/deps/deps_check.dart';

/// PreToolUse hook: validates Dart/Flutter package additions against pub.dev.
///
/// Usage:
///   dart run bin/deps_check.dart --mode=pub-add
///   dart run bin/deps_check.dart --mode=pubspec-guard
///
/// Reads tool input JSON from stdin. Always exits 0 (warnings only — the
/// agent decides whether to proceed).
void main(List<String> args) async {
  final parser =
      ArgParser()..addOption('mode', allowed: ['pub-add', 'pubspec-guard']);

  final ArgResults results;
  try {
    results = parser.parse(args);
  } on ArgParserException catch (e) {
    stderr.writeln('deps_check: ${e.message}');
    exit(0); // Fail open.
  }

  final String? mode = results['mode'] as String?;
  if (mode == null) {
    stderr.writeln(
      'deps_check: --mode is required. Pass --mode=pub-add or --mode=pubspec-guard',
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

  if (mode == 'pub-add') {
    await handlePubAdd(input);
  } else {
    await handlePubspecGuard(input);
  }

  // We call `exit` explicitly here in case any network calls - to pub? - would
  // otherwise delay exit.
  exit(0);
}
