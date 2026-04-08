import 'dart:convert';
import 'dart:io';

import 'package:flutter_slipstream/src/inspector/diagnostics_node.dart';
import 'package:flutter_slipstream/src/inspector/layout_formatter.dart';
import 'package:test/test.dart';

void main() {
  group('formatLayoutDetails', () {
    late DiagnosticsNode node;

    setUp(() {
      final data =
          jsonDecode(
                File(
                  'test/inspector/fixtures/render_trees/overflow_details.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      node = DiagnosticsNode.fromJson(data);
    });

    test('matches golden output', () {
      final golden =
          File(
            'test/inspector/fixtures/render_trees/overflow_details_formatted.txt',
          ).readAsStringSync().trimRight();
      // maxDepth: 1 matches the default used by inspect_layout.
      expect(formatLayoutDetails(node, maxDepth: 1), equals(golden));
    });

    test('truncates beyond maxChildren', () {
      // Pass maxChildren=3 to force truncation on a 20-child node.
      final output = formatLayoutDetails(node, maxChildren: 3);
      expect(output, contains('... (17 more children)'));
    });

    test('respects maxDepth=0 (no children)', () {
      final output = formatLayoutDetails(node, maxDepth: 0);
      expect(output, isNot(contains('children')));
    });
  });
}
