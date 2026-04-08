import 'dart:convert';
import 'dart:io';

import 'package:flutter_slipstream/src/inspector/diagnostics_node.dart';
import 'package:flutter_slipstream/src/inspector/route_formatter.dart';
import 'package:test/test.dart';

void main() {
  group('formatRouteInfo', () {
    late DiagnosticsNode root;

    setUpAll(() {
      final data =
          jsonDecode(
                File(
                  'test/inspector/fixtures/route_widget_tree.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      root = DiagnosticsNode.fromJson(data);
    });

    test('finds navigators', () {
      final output = formatRouteInfo(root);
      expect(output, isNotEmpty);
      expect(output, contains('Route stack'));
    });

    test('identifies current route', () {
      final output = formatRouteInfo(root);
      expect(output, contains('← current'));
      // Only the content navigator is shown; exactly one current marker.
      expect('← current'.allMatches(output).length, equals(1));
    });

    test('suppresses navigators whose routes are all private widgets', () {
      final output = formatRouteInfo(root);
      // The go_router shell navigator (_AppShell) should be filtered out.
      expect(output, isNot(contains('_AppShell')));
      // With only one visible navigator, the "Navigator:" header is omitted.
      expect(output, isNot(contains('Navigator:')));
    });

    test('resolves local screen widget names', () {
      final output = formatRouteInfo(root);
      expect(output, contains('PlaylistScreen'));
      expect(output, contains('EpisodeDetailScreen'));
    });

    test('includes short file paths', () {
      final output = formatRouteInfo(root);
      // Screen widgets are created in lib/app/routes.dart.
      expect(output, contains('lib/app/routes.dart'));
    });

    test('does not surface pub-cache paths', () {
      final output = formatRouteInfo(root);
      expect(output, isNot(contains('.pub-cache')));
    });
  });
}
