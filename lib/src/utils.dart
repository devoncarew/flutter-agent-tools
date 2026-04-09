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

Object? jsonTryParse(String source) {
  try {
    return jsonDecode(source);
  } catch (e) {
    return null;
  }
}
