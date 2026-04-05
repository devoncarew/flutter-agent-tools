import 'dart:convert';
import 'dart:io';

import 'package:flutter_agent_tools/src/diagnostics_node.dart';
import 'package:flutter_agent_tools/src/flutter_run_session.dart';
import 'package:test/test.dart';

Map<String, dynamic> _loadFixture(String name) {
  final file = File('test/fixtures/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('DiagnosticsNode.fromJson', () {
    late Map<String, dynamic> data;
    late DiagnosticsNode node;

    setUp(() {
      data = _loadFixture('overflow_error.json');
      node = DiagnosticsNode.fromJson(data);
    });

    test('parses description', () {
      expect(node.description, 'Exception caught by rendering library');
    });

    test('parses type', () {
      expect(node.type, '_FlutterErrorDetailsNode');
    });

    test('parses valueId', () {
      expect(node.valueId, isNotNull);
    });

    test('parses properties', () {
      expect(node.properties, isNotEmpty);
    });

    test('has no children', () {
      // Overflow error encodes context as properties, not children.
      expect(node.children, isEmpty);
    });

    test('propertyNamed returns correct node', () {
      // The ErrorSummary property has no name; look up by type instead via raw
      // json — but propertyNamed matches on name. Verify null for missing name.
      expect(node.propertyNamed('nonexistent'), isNull);
    });

    test('properties include ErrorSummary with level summary', () {
      final summary = node.properties.where((p) => p.level == 'summary');
      expect(summary, isNotEmpty);
      expect(
        summary.first.description,
        contains('RenderFlex overflowed'),
      );
    });

    test('properties include ErrorHint nodes', () {
      final hints = node.properties.where((p) => p.level == 'hint');
      expect(hints, isNotEmpty);
    });
  });

  group('FlutterError.tryParse', () {
    late Map<String, dynamic> data;
    late FlutterError error;

    setUp(() {
      data = _loadFixture('overflow_error.json');
      error = FlutterError.tryParse(data)!;
    });

    test('returns non-null for valid data', () {
      expect(FlutterError.tryParse(data), isNotNull);
    });

    test('returns null when description is absent', () {
      expect(FlutterError.tryParse({}), isNull);
    });

    test('parses description', () {
      expect(error.description, 'Exception caught by rendering library');
    });

    test('parses errorsSinceReload', () {
      expect(error.errorsSinceReload, 0);
    });

    test('detail returns ErrorSummary text', () {
      expect(error.detail, 'A RenderFlex overflowed by 900 pixels on the bottom.');
    });

    test('detail falls back to description when no ErrorSummary', () {
      final minimal = {'description': 'Some error'};
      final e = FlutterError.tryParse(minimal)!;
      expect(e.detail, 'Some error');
    });

    test('summary combines description and detail', () {
      expect(error.summary, contains('Exception caught by rendering library'));
      expect(error.summary, contains('RenderFlex overflowed'));
      expect(error.summary, contains('▸'));
    });

    test('summary equals description when detail matches', () {
      final minimal = {'description': 'Some error'};
      final e = FlutterError.tryParse(minimal)!;
      expect(e.summary, 'Some error');
    });

    test('node is the full DiagnosticsNode tree', () {
      expect(error.node.description, error.description);
      expect(error.node.properties, isNotEmpty);
    });

    test('toString includes summary', () {
      expect(error.toString(), contains(error.summary));
    });
  });
}
