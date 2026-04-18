import 'dart:io';

import 'package:http/http.dart' as http;

import 'deps_check.dart';

// --- Gemini input:

// {
//   "session_id": "...",
//   "cwd": "/users/dev/project",
//   "hook_event_name": "BeforeTool",
//   "tool_name": "run_shell_command",
//   "tool_input": {
//     "command": "npm install lodash"
//   }
// }

// {
//   "session_id": "string",
//   "cwd": "string",
//   "hook_event_name": "BeforeTool",
//   "tool_name": "write_file",
//   "tool_input": {
//     "path": "src/main.ts",
//     "content": "..."
//   },
//   "messages": [...],
//   "timestamp": "2026-04-17T..."
// }
// For 'write_file', 'tool_input' includes 'path' and 'content'.
// For 'replace', 'tool_input' includes 'path', 'old_string', and 'new_string'.

// Gemini output:

// - 'decision' string; "allow", "deny", or "block".
// - 'reason' string; Required if denied. This message is shown to the model
//   so it can attempt to self-correct.
// - 'systemMessage' string; shown to user - ignored by the model

/// Handles a `flutter pub add` / `dart pub add` BeforeTool hook invocation
/// (Gemini CLI).
Future<List<String>> handlePubAddGemini(
  Map<String, Object?> input, {
  http.Client? httpClient,
}) async {
  final toolName = input['tool_name'] as String?;
  if (toolName != 'run_shell_command') return const [];

  final command = (input['tool_input'] as Map?)?['command'] as String? ?? '';
  if (!RegExp(r'(flutter|dart)\s+pub\s+add').hasMatch(command)) return const [];

  final packages = extractPackagesFromCommand(command);
  if (packages.isEmpty) return const [];

  return await checkPackages(packages, httpClient: httpClient);
}

/// Handles a write_file/replace BeforeTool hook invocation targeting
/// `pubspec.yaml` (Gemini CLI).
Future<List<String>> handlePubspecGuardGemini(
  Map<String, Object?> input, {
  http.Client? httpClient,
}) async {
  final toolName = input['tool_name'] as String?;
  if (toolName != 'write_file' && toolName != 'replace') return const [];

  final toolArgs = (input['tool_input'] as Map?)?.cast<String, Object?>() ?? {};
  final filePath = toolArgs['path'] as String? ?? '';

  if (!filePath.endsWith('pubspec.yaml')) return const [];

  String oldContent = '';
  try {
    oldContent = File(filePath).readAsStringSync();
  } catch (_) {
    // File doesn't exist yet — treat all incoming deps as new.
  }

  final String newContent;
  if (toolName == 'write_file') {
    newContent = toolArgs['content'] as String? ?? '';
  } else {
    // replace: apply old_string → new_string substitution.
    final oldString = toolArgs['old_string'] as String? ?? '';
    final newString = toolArgs['new_string'] as String? ?? '';
    newContent = oldContent.replaceFirst(oldString, newString);
  }

  final added = newlyAddedPackages(oldContent, newContent);
  if (added.isEmpty) return const [];
  return await checkPackages(added, httpClient: httpClient);
}

Map<String, Object> geminiValidationFailure(List<String> warnings) {
  // We want {'decision': 'deny', 'reason': ...} here; it's the softest failure
  // that the agent will notice. The agent won't see a 'systemMessage'.

  final message = warnings.join('\n');
  return {'decision': 'deny', 'reason': message};
}
