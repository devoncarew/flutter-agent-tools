import 'dart:convert';

Object? jsonTryParse(String source) {
  try {
    return jsonDecode(source);
  } catch (e) {
    return null;
  }
}
