import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

void main(List<String> args) {
  final parser =
      ArgParser()
        ..addMultiOption(
          'keys',
          help: 'Top-level key that must be present (repeatable).',
        )
        ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults results;
  try {
    results = parser.parse(args);
  } on ArgParserException catch (e) {
    stderr.writeln('validate_manifest: ${e.message}');
    exit(1);
  }

  if (results['help'] as bool) {
    stdout.writeln(
      'Usage: dart tool/validate_manifest.dart [options] <manifest.json>',
    );
    stdout.writeln(parser.usage);
    exit(0);
  }

  if (results.rest.isEmpty) {
    stderr.writeln('Usage: dart tool/validate_manifest.dart <manifest.json>');
    exit(1);
  }

  final requiredKeys = results.multiOption('keys');

  var failed = false;

  for (final filePath in results.rest) {
    final file = File(filePath);
    if (!file.existsSync()) {
      stderr.writeln('File not found: $filePath');
      failed = true;
      continue;
    }

    final Map<String, Object?> json;
    try {
      json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    } on FormatException catch (e) {
      stderr.writeln('$filePath: invalid JSON — $e');
      failed = true;
      continue;
    }

    final missing = requiredKeys.where((k) => !json.containsKey(k)).toList();
    if (missing.isNotEmpty) {
      stderr.writeln('$filePath: missing fields: ${missing.join(', ')}');
      failed = true;
      continue;
    }

    print('$filePath: ok');
  }

  if (failed) {
    exit(1);
  }
}
