import 'dart:io';

import 'package:yaml/yaml.dart';

/// The package version read from `pubspec.yaml` in the working directory.
///
/// Falls back to `'0.0.0'` if the file cannot be read or parsed.
final String packageVersion = _readVersion();

String _readVersion() {
  try {
    final yaml = loadYaml(File('pubspec.yaml').readAsStringSync());
    if (yaml is Map) return yaml['version'] as String? ?? '0.0.0';
  } catch (_) {}
  return '0.0.0';
}
