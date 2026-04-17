import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'blocklist.dart';

// ---------------------------------------------------------------------------
// Claude PreToolUse handlers

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
    // Edit: apply old_string → new_string substitution.
    final oldString = toolInput['old_string'] as String? ?? '';
    final newString = toolInput['new_string'] as String? ?? '';
    newContent = oldContent.replaceFirst(oldString, newString);
  }

  final added = newlyAddedPackages(oldContent, newContent);
  if (added.isEmpty) return const [];
  return await checkPackages(added, httpClient: httpClient);
}

// ---------------------------------------------------------------------------
// Gemini BeforeTool handlers

/// Handles a `flutter pub add` / `dart pub add` BeforeTool hook invocation
/// (Gemini CLI).
///
/// Gemini input uses `tool_arguments` (not `tool_input`) and the tool name is
/// `run_shell_command` (not `Bash`). Returns any warning strings. Never throws.
Future<List<String>> handlePubAddGemini(
  Map<String, Object?> input, {
  http.Client? httpClient,
}) async {
  final toolName = input['tool_name'] as String?;
  if (toolName != 'run_shell_command') return const [];

  final command =
      (input['tool_arguments'] as Map?)?['command'] as String? ?? '';
  if (!RegExp(r'(flutter|dart)\s+pub\s+add').hasMatch(command)) return const [];

  final packages = extractPackagesFromCommand(command);
  if (packages.isEmpty) return const [];

  return await checkPackages(packages, httpClient: httpClient);
}

/// Handles a write_file/replace BeforeTool hook invocation targeting
/// `pubspec.yaml` (Gemini CLI).
///
/// Gemini input uses `tool_arguments` with `path` (not `tool_input.file_path`),
/// and tool names are `write_file` / `replace` (not `Write` / `Edit`). Returns
/// any warning strings. Never throws.
Future<List<String>> handlePubspecGuardGemini(
  Map<String, Object?> input, {
  http.Client? httpClient,
}) async {
  final toolName = input['tool_name'] as String?;
  if (toolName != 'write_file' && toolName != 'replace') return const [];

  final toolArgs =
      (input['tool_arguments'] as Map?)?.cast<String, Object?>() ?? {};
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

// ---------------------------------------------------------------------------
// common

/// Extracts `[(packageName, versionConstraint?)]` from a `pub add` command.
///
/// Examples:
/// - `flutter pub add http` → `[('http', null)]`
/// - `flutter pub add 'http:^0.13.0' provider` →
///   `[('http', '^0.13.0'), ('provider', null)]`
List<(String, String?)> extractPackagesFromCommand(String command) {
  final withoutCmd =
      command.replaceAll(RegExp(r'(flutter|dart)\s+pub\s+add\s*'), '').trim();

  final results = <(String, String?)>[];
  for (final token in withoutCmd.split(RegExp(r'\s+'))) {
    if (token.isEmpty || token.startsWith('-')) continue;
    final clean = token.replaceAll(RegExp("['\"]"), '');
    final colonIdx = clean.indexOf(':');
    if (colonIdx > 0) {
      results.add((
        clean.substring(0, colonIdx),
        clean.substring(colonIdx + 1),
      ));
    } else {
      results.add((clean, null));
    }
  }
  return results;
}

/// Returns the list of packages newly added between [oldContent] and
/// [newContent] (both raw pubspec.yaml strings), as
/// `[(packageName, versionConstraint?)]`.
///
/// Only packages absent from [oldContent] and present in [newContent] are
/// returned. Constraint changes to existing packages are ignored.
List<(String, String?)> newlyAddedPackages(
  String oldContent,
  String newContent,
) {
  final oldDeps = parsePubspecDeps(oldContent);
  final newDeps = parsePubspecDeps(newContent);

  final added = <(String, String?)>[];
  for (final entry in newDeps.entries) {
    if (!oldDeps.containsKey(entry.key)) {
      added.add((entry.key, entry.value.isEmpty ? null : entry.value));
    }
  }
  return added;
}

/// Parses a pubspec.yaml string and returns a flat map of
/// `package → constraint` for all entries in `dependencies` and
/// `dev_dependencies`.
Map<String, String> parsePubspecDeps(String content) {
  final result = <String, String>{};
  try {
    final yaml = loadYaml(content);
    if (yaml is! Map) return result;
    for (final section in ['dependencies', 'dev_dependencies']) {
      final deps = yaml[section];
      if (deps is! Map) continue;
      for (final key in deps.keys) {
        final value = deps[key];
        result[key as String] =
            value is String ? value : (value?.toString() ?? '');
      }
    }
  } catch (_) {
    // Malformed YAML — fail open.
  }
  return result;
}

/// Checks [packages] against the blocklist and pub.dev, returning any warning
/// strings. Never throws.
///
/// [httpClient] is used for pub.dev requests; defaults to a new [http.Client].
/// Pass a custom client in tests to avoid real network calls.
Future<List<String>> checkPackages(
  List<(String, String?)> packages, {
  http.Client? httpClient,
}) async {
  final client = httpClient ?? http.Client();
  final warnings = <String>[];

  for (final (pkg, requestedConstraint) in packages) {
    // Check unofficial blocklist before hitting pub.dev.
    final blocklistEntry =
        unofficialBlocklist.where((e) => e.package == pkg).firstOrNull;
    if (blocklistEntry != null) {
      final suffix =
          blocklistEntry.suggestion != null
              ? '; consider ${blocklistEntry.suggestion} instead'
              : '';
      warnings.add("  ⚠  '$pkg': ${blocklistEntry.reason}$suffix");
      // Still check pub.dev for discontinued status and version warnings.
    }

    final info = await fetchPubDevInfo(pkg, client);
    if (info == null) {
      warnings.add("  ⚠  '$pkg': could not reach pub.dev (proceeding anyway)");
      continue;
    }

    if (info['notFound'] == true) {
      warnings.add(
        "  ⚠  '$pkg': package not found on pub.dev — verify the name before adding",
      );
      continue;
    }

    final isDiscontinued = info['isDiscontinued'] as bool? ?? false;
    final replacedBy = info['replacedBy'] as String?;
    final latestVersionStr = info['latestVersion'] as String?;

    if (isDiscontinued) {
      warnings.add(
        replacedBy != null
            ? "  ⚠  '$pkg' is discontinued. Official replacement: '$replacedBy'"
            : "  ⚠  '$pkg' is discontinued with no official replacement listed",
      );
      continue; // Skip major-version check for discontinued packages.
    }

    if (requestedConstraint != null &&
        latestVersionStr != null &&
        requestedConstraint.isNotEmpty) {
      final w = checkMajorVersion(pkg, requestedConstraint, latestVersionStr);
      if (w != null) warnings.add(w);
    }
  }

  return warnings;
}

/// Returns a warning string if [requestedConstraint] targets an older major
/// version than [latestVersionStr], or null if the versions are compatible.
String? checkMajorVersion(
  String pkg,
  String requestedConstraint,
  String latestVersionStr,
) {
  try {
    final latest = Version.parse(latestVersionStr);
    final floor = requestedConstraint.replaceAll(RegExp(r'^[\^~><=]+'), '');
    if (floor.isEmpty) return null;
    final requested = Version.parse(floor);
    if (requested.major < latest.major) {
      return "  ⚠  '$pkg': you're requesting major version ${requested.major} "
          "(v$requestedConstraint) but the current major is ${latest.major} "
          "(v$latestVersionStr) — consider using the latest major version";
    }
  } catch (_) {
    // Unparseable version — skip check.
  }
  return null;
}

/// Fetches package metadata from pub.dev.
///
/// Returns a map with keys `isDiscontinued`, `replacedBy`, `latestVersion`,
/// or `{'notFound': true}` for a 404. Returns null on network errors.
Future<Map<String, Object?>?> fetchPubDevInfo(
  String pkg,
  http.Client client,
) async {
  try {
    final uri = Uri.parse('https://pub.dev/api/packages/$pkg');
    final response = await client.get(uri).timeout(const Duration(seconds: 8));

    if (response.statusCode == 404) return {'notFound': true};
    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, Object?>;
    final latest = body['latest'] as Map<String, Object?>?;

    return {
      'isDiscontinued': body['isDiscontinued'] as bool? ?? false,
      'replacedBy': body['replacedBy'] as String?,
      'latestVersion': latest?['version'] as String?,
    };
  } catch (_) {
    return null; // Network error — fail open.
  }
}
