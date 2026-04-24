import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'deps_check.dart';

// Copilot input format (camelCase fields; toolArgs is a double-encoded JSON string):
//
// {
//   "sessionId": "...",
//   "timestamp": 1234567890,
//   "cwd": "/path/to/project",
//   "toolName": "bash",
//   "toolArgs": "{\"command\":\"flutter pub add lints\",...}"
// }
//
// {
//   "sessionId": "...",
//   "timestamp": 1234567890,
//   "cwd": "/path/to/project",
//   "toolName": "edit",
//   "toolArgs": "{\"path\":\"/path/pubspec.yaml\",\"old_str\":\"...\",\"new_str\":\"...\"}"
// }
//
// Copilot output format:
// {
//   "permissionDecision": "allow" | "deny" | "ask",
//   "permissionDecisionReason": "..."
// }

Map<String, Object?> _decodeToolArgs(Map<String, Object?> input) {
  final raw = input['toolArgs'] as String? ?? '';
  try {
    return (jsonDecode(raw) as Map).cast<String, Object?>();
  } catch (_) {
    return const {};
  }
}

/// Handles a `flutter pub add` / `dart pub add` preToolUse hook invocation
/// (GitHub Copilot).
Future<List<String>> handlePubAddCopilot(
  Map<String, Object?> input, {
  http.Client? httpClient,
}) async {
  if (input['toolName'] != 'bash') return const [];

  final toolArgs = _decodeToolArgs(input);
  final command = toolArgs['command'] as String? ?? '';
  if (!RegExp(r'(flutter|dart)\s+pub\s+add').hasMatch(command)) return const [];

  final packages = extractPackagesFromCommand(command);
  if (packages.isEmpty) return const [];

  return await checkPackages(packages, httpClient: httpClient);
}

/// Handles an edit preToolUse hook invocation targeting `pubspec.yaml`
/// (GitHub Copilot).
Future<List<String>> handlePubspecGuardCopilot(
  Map<String, Object?> input, {
  http.Client? httpClient,
}) async {
  if (input['toolName'] != 'edit') return const [];

  final cwd = input['cwd'] as String? ?? '.';
  final toolArgs = _decodeToolArgs(input);
  final filePath = toolArgs['path'] as String? ?? '';

  if (!filePath.endsWith('pubspec.yaml')) return const [];

  String oldContent = '';
  try {
    final fullPath =
        path.isAbsolute(filePath) ? filePath : path.join(cwd, filePath);
    oldContent = File(fullPath).readAsStringSync();
  } catch (_) {
    // File doesn't exist yet — treat all incoming deps as new.
  }

  // Copilot edit args use 'old_str'/'new_str' (not 'old_string'/'new_string').
  final oldStr = toolArgs['old_str'] as String? ?? '';
  final newStr = toolArgs['new_str'] as String? ?? '';
  final newContent = oldContent.replaceFirst(oldStr, newStr);

  final added = newlyAddedPackages(oldContent, newContent);
  if (added.isEmpty) return const [];
  return await checkPackages(added, httpClient: httpClient);
}

// Valid decisions are ask, deny, and allow.
Map<String, Object> copilotValidationFailure(List<String> warnings) {
  return {
    'permissionDecision': 'ask',
    'permissionDecisionReason': warnings.join('\n'),
  };
}
