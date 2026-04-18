import 'dart:io';

import 'package:http/http.dart' as http;

import 'deps_check.dart';

// Claude docs at https://code.claude.com/docs/en/hooks.

// -- Claude input:

// {
//   "event": "PreToolUse", // Type of event (e.g., PreToolUse, PostToolUse) [11]
//   "tool_name": "Bash",    // Name of the tool (e.g., Bash, Edit, Write, Glob) [1, 14]
//   "tool_input": {         // The payload sent to the tool
//     "command": "rm -rf /tmp/build" // Example payload for Bash [1]
//   },
//   "subagent": false,      // Boolean indicating if it's a subagent action [1]
//   "session_id": "..."     // Unique session identifier
// }

// {
//   "tool_name": "Write",
//   "tool_input": {
//     "file_path": "src/utils/math.ts",
//     "content": "export const add = (a: number, b: number) => a + b;"
//   }
// }

// {
//   "tool_name": "Edit",
//   "tool_input": {
//     "file_path": "src/app.ts",
//     "old_string": "const version = '1.0.0';",
//     "new_string": "const version = '1.1.0';"
//   }
// }

// -- Claude output:

// {
//   "hookSpecificOutput": {
//     "hookEventName": "PreToolUse",
//     "permissionDecision": "deny", (or "ask", ...)
//     "permissionDecisionReason": "Database writes are not allowed"
//   }
// }

/// Handles a `flutter pub add` / `dart pub add` hook invocation (Claude).
///
/// [input] is the decoded hook JSON from stdin. Returns any warning strings.
/// Never throws.
Future<List<String>> handlePubAddClaude(
  Map<String, Object?> input, {
  http.Client? httpClient,
}) async {
  final toolName = input['tool_name'] as String?;
  if (toolName != 'Bash') return const [];

  final command = (input['tool_input'] as Map?)?['command'] as String? ?? '';
  if (!RegExp(r'(flutter|dart)\s+pub\s+add').hasMatch(command)) return const [];

  final packages = extractPackagesFromCommand(command);
  if (packages.isEmpty) return const [];

  return await checkPackages(packages, httpClient: httpClient);
}

/// Handles a Write/Edit hook invocation targeting `pubspec.yaml` (Claude).
///
/// [input] is the decoded hook JSON from stdin. Returns any warning strings.
/// Never throws.
Future<List<String>> handlePubspecGuardClaude(
  Map<String, Object?> input, {
  http.Client? httpClient,
}) async {
  final toolName = input['tool_name'] as String?;
  if (toolName != 'Write' && toolName != 'Edit') return const [];

  final toolInput =
      (input['tool_input'] as Map?)?.cast<String, Object?>() ?? {};
  final filePath = toolInput['file_path'] as String? ?? '';

  if (!filePath.endsWith('pubspec.yaml')) return const [];

  // Read the current file from disk (before the edit).
  String oldContent = '';
  try {
    oldContent = File(filePath).readAsStringSync();
  } catch (_) {
    // File doesn't exist yet or unreadable — treat all incoming deps as new.
  }

  // Reconstruct the new file content.
  final String newContent;
  if (toolName == 'Write') {
    newContent = toolInput['content'] as String? ?? '';
  } else {
    // Note: claude also supports a bool 'replace_all', which we're currently
    // ignoring.

    // Edit: apply old_string → new_string substitution.
    final oldString = toolInput['old_string'] as String? ?? '';
    final newString = toolInput['new_string'] as String? ?? '';
    newContent = oldContent.replaceFirst(oldString, newString);
  }

  final added = newlyAddedPackages(oldContent, newContent);
  if (added.isEmpty) return const [];
  return await checkPackages(added, httpClient: httpClient);
}

Map<String, Object> claudeValidationFailure(List<String> warnings) {
  final message = warnings.join('\n');

  return {
    'hookSpecificOutput': {
      'hookEventName': 'PreToolUse',
      'permissionDecision': 'ask',
      'permissionDecisionReason': message,
    },
  };
}
