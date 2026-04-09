import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// The plugin version is read from `.claude-plugin/plugin.json` in the working
/// directory.
///
/// Falls back to `'0.0.0'` if the file cannot be read or parsed.
final String packageVersion = _readVersion();

String _readVersion() {
  try {
    final contents =
        File(path.join('.claude-plugin', 'plugin.json')).readAsStringSync();
    final json = jsonDecode(contents);
    return json['version'] as String;
  } catch (_) {}

  return '0.0.0';
}

class ToolException {
  final String message;

  ToolException(this.message);

  @override
  String toString() => 'ToolException: $message';
}

typedef DebugLogger = void Function(String message);
