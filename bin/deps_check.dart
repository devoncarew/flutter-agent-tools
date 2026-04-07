import 'dart:convert';
import 'dart:io';

import 'package:flutter_agent_tools/src/deps/deps_check.dart';

/// PreToolUse hook: validates Dart/Flutter package additions against pub.dev.
///
/// Usage:
///   dart run flutter_agent_tools:dep_check --mode=pub-add
///   dart run flutter_agent_tools:dep_check --mode=pubspec-guard
///
/// Reads tool input JSON from stdin. Always exits 0 (warnings only — the
/// agent decides whether to proceed).
void main(List<String> args) async {
  final String mode;
  if (args.contains('--mode=pub-add')) {
    mode = 'pub-add';
  } else if (args.contains('--mode=pubspec-guard')) {
    mode = 'pubspec-guard';
  } else {
    stderr.writeln(
      'dep_check: unknown mode. Pass --mode=pub-add or --mode=pubspec-guard',
    );
    exit(0); // Fail open.
  }

  final String rawInput;
  try {
    rawInput = await stdin.transform(utf8.decoder).join();
  } catch (_) {
    exit(0);
  }

  final Map<String, dynamic> input;
  try {
    input = (jsonDecode(rawInput) as Map).cast<String, dynamic>();
  } catch (_) {
    exit(0);
  }

  if (mode == 'pub-add') {
    await handlePubAdd(input);
  } else {
    await handlePubspecGuard(input);
  }
}
