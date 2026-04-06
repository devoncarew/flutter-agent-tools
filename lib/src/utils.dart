import 'dart:convert';
import 'dart:math';

import 'package:unique_names_generator/unique_names_generator.dart';

Object? jsonTryParse(String source) {
  try {
    return jsonDecode(source);
  } catch (e) {
    return null;
  }
}

typedef Logger = void Function(String);

class IdGenerator {
  final Random _random = Random();
  final UniqueNamesGenerator _nameGenerator = UniqueNamesGenerator(
    config: Config(
      length: 2,
      dictionaries: [adjectives, animals],
      separator: '_',
    ),
  );

  String createNextId() {
    final String suffix =
        List.generate(
          2,
          (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    return [_nameGenerator.generate(), suffix].join('_');
  }
}
