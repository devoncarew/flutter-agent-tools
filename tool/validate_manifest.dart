import 'dart:convert';
import 'dart:io';

const List<String> _required = [
  'name',
  'version',
  'description',
  'repository',
  'license',
  'keywords',
  'mcpServers',
];

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart tool/validate_manifest.dart <path>');
    exit(1);
  }

  final file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('File not found: ${file.path}');
    exit(1);
  }

  final Map<String, Object?> json;
  try {
    json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } on FormatException catch (e) {
    stderr.writeln('${file.path}: invalid JSON — $e');
    exit(1);
  }

  final missing = _required.where((k) => !json.containsKey(k)).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('${file.path}: missing fields: ${missing.join(', ')}');
    exit(1);
  }

  print('${file.path}: ok');
}
