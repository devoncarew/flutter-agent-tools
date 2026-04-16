import 'dart:convert';

/// Coerces [value] to an [int], accepting both Dart [int] and numeric strings.
///
/// Returns null if [value] is null or cannot be parsed as an integer.
/// This is used in tool handlers because MCP clients sometimes send integer
/// arguments as JSON strings rather than JSON numbers.
int? coerceInt(Object? value) => switch (value) {
  int i => i,
  String s => int.tryParse(s),
  _ => null,
};

/// Coerces [value] to a [bool], accepting both Dart [bool] and the strings
/// "true"/"false".
///
/// Returns null if [value] is null or cannot be parsed as a bool.
/// This is used in tool handlers for the same reason as [coerceInt].
bool? coerceBool(Object? value) => switch (value) {
  bool b => b,
  String s => switch (s.toLowerCase()) {
    'true' => true,
    'false' => false,
    _ => null,
  },
  _ => null,
};

double? coerceDouble(Object? value) {
  if (value == null) return null;
  return switch (value) {
    num n => n.toDouble(),
    String s => double.tryParse(s),
    _ => null,
  };
}

Object? jsonTryParse(String source) {
  try {
    return jsonDecode(source);
  } catch (e) {
    return null;
  }
}

/// Describe a short duration. This may return '100ms' or it may return '6.1s'.
String? describeShortDuration(Duration? elapsed) {
  if (elapsed == null) return null;

  final ms = elapsed.inMilliseconds;

  if (ms < 1000) {
    return '${ms}ms';
  } else {
    final s = ms / 1000.0;
    return '${s.toStringAsFixed(1)}s';
  }
}
