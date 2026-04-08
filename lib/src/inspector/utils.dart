import 'dart:convert';
import 'dart:math';

Object? jsonTryParse(String source) {
  try {
    return jsonDecode(source);
  } catch (e) {
    return null;
  }
}

typedef Logger = void Function(String);

class IdGenerator {
  static const List<String> _adjectives = [
    'bright',
    'calm',
    'cozy',
    'crisp',
    'deft',
    'fair',
    'fond',
    'free',
    'glad',
    'keen',
    'kind',
    'lush',
    'mild',
    'mint',
    'neat',
    'nimble',
    'pure',
    'rosy',
    'sage',
    'snug',
    'soft',
    'spry',
    'sunny',
    'swift',
    'warm',
    'wise',
    'witty',
    'zippy',
  ];

  static const List<String> _animals = [
    'bee',
    'cat',
    'colt',
    'deer',
    'dove',
    'duck',
    'fawn',
    'finch',
    'fox',
    'frog',
    'gull',
    'hare',
    'hawk',
    'jay',
    'koi',
    'lamb',
    'lark',
    'lynx',
    'newt',
    'owl',
    'pony',
    'quail',
    'robin',
    'seal',
    'swan',
    'teal',
    'wren',
  ];

  final Random _random = Random();

  String createNextId() {
    final adjective = _adjectives[_random.nextInt(_adjectives.length)];
    final animal = _animals[_random.nextInt(_animals.length)];
    final number = _random.nextInt(100).toString().padLeft(2, '0');
    return '${adjective}_${animal}_$number';
  }
}
