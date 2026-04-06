// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_agent_tools/src/dep/blocklist.dart';
import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

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
      'dep_check: unknown mode. Pass --mode=pub-add or '
      '--mode=pubspec-guard',
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
    await _handlePubAdd(input);
  } else {
    await _handlePubspecGuard(input);
  }
}

// ---------------------------------------------------------------------------
// pub-add mode

Future<void> _handlePubAdd(Map<String, dynamic> input) async {
  final toolName = input['tool_name'] as String?;
  if (toolName != 'Bash') return;

  final command = (input['tool_input'] as Map?)?['command'] as String? ?? '';
  if (!RegExp(r'(flutter|dart)\s+pub\s+add').hasMatch(command)) return;

  // Extract package name + optional version from the command.
  // e.g. `flutter pub add http` → [('http', null)]
  // e.g. `flutter pub add 'http:^0.13.0' provider` → [('http', '^0.13.0'), ('provider', null)]
  final packages = _extractPackagesFromCommand(command);
  if (packages.isEmpty) return;

  await _checkPackages(packages);
}

/// Extracts [(packageName, versionConstraint?)] from a pub add command string.
List<(String, String?)> _extractPackagesFromCommand(String command) {
  final withoutCmd =
      command.replaceAll(RegExp(r'(flutter|dart)\s+pub\s+add\s*'), '').trim();

  final results = <(String, String?)>[];
  for (final token in withoutCmd.split(RegExp(r'\s+'))) {
    if (token.isEmpty || token.startsWith('-')) continue;
    // Strip surrounding quotes
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

// ---------------------------------------------------------------------------
// pubspec-guard mode

Future<void> _handlePubspecGuard(Map<String, dynamic> input) async {
  final toolName = input['tool_name'] as String?;
  if (toolName != 'Write' && toolName != 'Edit') return;

  final toolInput =
      (input['tool_input'] as Map?)?.cast<String, dynamic>() ?? {};
  final filePath = toolInput['file_path'] as String? ?? '';

  if (!filePath.endsWith('pubspec.yaml')) return;

  // Read the current file from disk (before the edit).
  Map<String, String> oldDeps = {};
  try {
    final currentContent = File(filePath).readAsStringSync();
    oldDeps = _parsePubspecDeps(currentContent);
  } catch (_) {
    // File doesn't exist yet or unreadable — treat all incoming deps as new.
  }

  // Get the new content depending on tool type.
  final String newContent;
  if (toolName == 'Write') {
    newContent = toolInput['content'] as String? ?? '';
  } else {
    // Edit: reconstruct new content from old_string → new_string substitution.
    final oldFile = File(filePath);
    final String currentContent =
        oldFile.existsSync() ? oldFile.readAsStringSync() : '';
    final oldString = toolInput['old_string'] as String? ?? '';
    final newString = toolInput['new_string'] as String? ?? '';
    newContent = currentContent.replaceFirst(oldString, newString);
  }

  final newDeps = _parsePubspecDeps(newContent);

  // Find packages added or with changed version constraints.
  final added = <(String, String?)>[];
  for (final entry in newDeps.entries) {
    final oldConstraint = oldDeps[entry.key];
    if (oldConstraint == null) {
      // Newly added package.
      added.add((entry.key, entry.value.isEmpty ? null : entry.value));
    }
    // We don't warn on constraint changes to existing packages — the agent
    // may be intentionally downgrading or tightening a constraint.
  }

  if (added.isEmpty) return;
  await _checkPackages(added);
}

/// Parses a pubspec.yaml string and returns a flat map of package → constraint
/// for all entries in `dependencies` and `dev_dependencies`.
Map<String, String> _parsePubspecDeps(String content) {
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

// ---------------------------------------------------------------------------
// pub.dev validation

Future<void> _checkPackages(List<(String, String?)> packages) async {
  final warnings = <String>[];

  for (final (pkg, requestedConstraint) in packages) {
    // Check unofficial blocklist before hitting pub.dev.
    final blocklistEntry =
        unofficialBlocklist.where((e) => e.package == pkg).firstOrNull;
    if (blocklistEntry != null) {
      final suggestion =
          blocklistEntry.suggestion != null
              ? '; consider ${blocklistEntry.suggestion} instead'
              : '';
      warnings.add("  ⚠  '$pkg': ${blocklistEntry.reason}$suggestion");
      // Still check pub.dev for discontinued status and version warnings.
    }

    final info = await _fetchPubDevInfo(pkg);
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
      if (replacedBy != null) {
        warnings.add(
          "  ⚠  '$pkg' is discontinued. Official replacement: '$replacedBy'",
        );
      } else {
        warnings.add(
          "  ⚠  '$pkg' is discontinued with no official replacement listed",
        );
      }
      // Skip major-version check for discontinued packages.
      continue;
    }

    // Warn if the requested constraint pins to an older major version.
    if (requestedConstraint != null &&
        latestVersionStr != null &&
        requestedConstraint.isNotEmpty) {
      final oldMajorWarning = _checkMajorVersion(
        pkg,
        requestedConstraint,
        latestVersionStr,
      );
      if (oldMajorWarning != null) warnings.add(oldMajorWarning);
    }
  }

  if (warnings.isNotEmpty) {
    print('flutter-agent-tools: dependency warnings:');
    for (final w in warnings) {
      print(w);
    }
  }
}

/// Returns a warning string if [requestedConstraint] targets an older major
/// version than [latestVersionStr], or null if the versions are compatible.
String? _checkMajorVersion(
  String pkg,
  String requestedConstraint,
  String latestVersionStr,
) {
  try {
    final latest = Version.parse(latestVersionStr);
    // Strip leading ^/~/>=/<= to get the floor version of the constraint.
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

// ---------------------------------------------------------------------------
// pub.dev HTTP

Future<Map<String, dynamic>?> _fetchPubDevInfo(String pkg) async {
  try {
    final uri = Uri.parse('https://pub.dev/api/packages/$pkg');
    final response = await http.get(uri).timeout(const Duration(seconds: 8));

    if (response.statusCode == 404) return {'notFound': true};
    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final latest = body['latest'] as Map<String, dynamic>?;

    return {
      'isDiscontinued': body['isDiscontinued'] as bool? ?? false,
      'replacedBy': body['replacedBy'] as String?,
      'latestVersion': latest?['version'] as String?,
    };
  } catch (_) {
    return null; // Network error — fail open.
  }
}
