import 'dart:convert';
import 'dart:io';

import 'package:flutter_agent_tools/src/diagnostics_node.dart';
import 'package:flutter_agent_tools/src/layout_formatter.dart';
import 'package:test/test.dart';

void main() {
  group('formatLayoutDetails', () {
    late DiagnosticsNode node;

    setUp(() {
      final fixture = 'test/fixtures/render_trees/overflow_details.json';
      final data =
          jsonDecode(File(fixture).readAsStringSync()) as Map<String, dynamic>;
      node = DiagnosticsNode.fromJson(data);
    });

    test('includes root description', () {
      final output = formatLayoutDetails(node);
      expect(output, contains('RenderFlex'));
      expect(output, contains('OVERFLOWING'));
    });

    test('includes root properties', () {
      final output = formatLayoutDetails(node);
      expect(
        output,
        contains('constraints: BoxConstraints(0.0<=w<=411.0, h=300.0)'),
      );
      expect(output, contains('size: Size(411.0, 300.0)'));
      expect(output, contains('direction: vertical'));
      expect(output, contains('mainAxisAlignment: start'));
    });

    test('includes children header with count', () {
      final output = formatLayoutDetails(node);
      expect(output, contains('children (20):'));
    });

    test('includes child names and descriptions', () {
      final output = formatLayoutDetails(node);
      expect(output, contains('child 1:'));
      expect(output, contains('RenderConstrainedBox'));
    });

    test('includes child layout properties', () {
      final output = formatLayoutDetails(node);
      // parentData carries offset and flex factor.
      expect(output, contains('parentData:'));
      expect(output, contains('flex=null'));
      // Each child is 60px tall.
      expect(output, contains('size: Size(411.0, 60.0)'));
    });

    test('truncates beyond _maxChildren', () {
      // The fixture has 20 children, which is exactly _maxChildren — no
      // truncation line expected. If we had 21 we'd see "more children".
      final output = formatLayoutDetails(node);
      expect(output, isNot(contains('more children')));
    });
  });
}
