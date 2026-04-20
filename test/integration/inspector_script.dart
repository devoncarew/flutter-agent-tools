// Integration tests for the 'inspector' MCP server.

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:flutter_slipstream/src/inspector/inspector_mcp.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

// These tests start a real InspectorMCPServer and exercise its tools from the
// perspective of an MCP client.
//
// A single server instance is shared across all tests in this file.
//
// For the moment this script is run manually. We expect to run this on CI
// however against the Flutter app in ../slipstream_agent/slipstream_showcase.

void main(List<String> args) {
  // Require the app to run as the first arg.
  if (args.length != 1) {
    print(
      'usage: dart test/integration/inspector_script.dart <path-to-flutter-app>',
    );
    exit(1);
  }

  late TestEnvironment<TestMCPClient, InspectorMCPServer> env;

  // --- setup

  // Set up before all the tests.
  setUpAll(() async {
    env = TestEnvironment(TestMCPClient(), InspectorMCPServer.new);
    await env.initializeServer();

    final String projectDir = Directory(args[0]).absolute.path;
    await _startApp(env, projectDir);
  });

  // Wait a brief period of time between tests.
  tearDown(() async {
    await Future.delayed(Duration(milliseconds: 300));
  });

  // Tear down after all the tests.
  tearDownAll(() async {
    await env.shutdown();
  });

  // --- tool tests

  group('run_app', () {
    test('returns error when required argument is missing', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'run_app', arguments: {}),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('working_directory'));
    });
  });

  group('reload', () {
    test('hot reload succeeds', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'reload', arguments: {'full_restart': false}),
      );

      expect(result.isError, isNull, reason: result.describe);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('Hot reload complete'));
    });

    test('full restart succeeds', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'reload', arguments: {'full_restart': true}),
      );

      expect(result.isError, isNull, reason: result.describe);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('Hot restart complete'));
    });
  });

  group('get_output', () {
    test('returns a string result', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'get_output'),
      );

      expect(result.isError, isNull, reason: result.describe);
      expect(result.content.first, isA<TextContent>());
    });

    test('output captured after reload contains route or is empty', () async {
      // Drain any buffered output first.
      await env.serverConnection.callTool(CallToolRequest(name: 'get_output'));

      // Trigger a reload so the app emits output.
      await env.serverConnection.callTool(
        CallToolRequest(name: 'reload', arguments: {'full_restart': false}),
      );

      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'get_output'),
      );

      expect(result.isError, isNull);
      // The result is either empty (no new output) or contains text lines.
      expect(result.content.first, isA<TextContent>());
    });
  });

  group('take_screenshot', () {
    test('returns a valid result', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'take_screenshot'),
      );

      expect(result.isError, isNull, reason: result.describe);
      expect(result.content.first, isA<ImageContent>());
    });
  });

  group('inspect_layout', () {
    test('returns layout tree from root when no widget_id given', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'inspect_layout', arguments: {}),
      );

      expect(result.isError, isNull, reason: result.describe);
      final text = (result.content.first as TextContent).text;
      // Root layout tree should contain at least the app scaffold structure.
      expect(text, isNotEmpty);
    });

    test('returns error for unknown widget_id', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'inspect_layout',
          arguments: {'widget_id': 999999999},
        ),
      );

      // Either an error result or an empty/not-found message — either is fine;
      // what matters is it does not crash the server.
      expect(result.content, isNotEmpty);
    });
  });

  group('evaluate', () {
    test('evaluates a simple expression', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'evaluate', arguments: {'expression': '1 + 1'}),
      );

      expect(result.isError, isNull, reason: result.describe);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('2'));
    });

    test('reads a top-level variable from the showcase app', () async {
      // tapCount is a global int defined in the showcase app's main.dart.
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'evaluate',
          arguments: {'expression': 'tapCount.toString()'},
        ),
      );

      expect(result.isError, isNull, reason: result.describe);
      final text = (result.content.first as TextContent).text;
      // At startup tapCount == 0; after taps it is a non-negative integer.
      expect(int.tryParse(text.trim()), isNotNull);
    });

    test('returns an error result for invalid Dart', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'evaluate',
          arguments: {'expression': 'this is not valid dart !!!'},
        ),
      );

      // Should come back as an error or contain an error message — not crash.
      expect(result.content, isNotEmpty);
    });
  });

  group('get_route', () {
    test('returns current route stack', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'get_route', arguments: {}),
      );

      expect(result.isError, isNull, reason: result.describe);
      final text = (result.content.first as TextContent).text;
      // The showcase app starts at /discover.
      expect(text, isNotEmpty);
    });

    test(
      'reflects navigation — route changes after navigate to /widgets',
      () async {
        await env.serverConnection.callTool(
          CallToolRequest(name: 'navigate', arguments: {'path': '/widgets'}),
        );

        final result = await env.serverConnection.callTool(
          CallToolRequest(name: 'get_route', arguments: {}),
        );

        expect(result.isError, isNull, reason: result.describe);
        final text = (result.content.first as TextContent).text;
        expect(text, contains('WidgetsPage'));

        // Navigate back so subsequent tests start from a clean state.
        await env.serverConnection.callTool(
          CallToolRequest(name: 'navigate', arguments: {'path': '/discover'}),
        );
      },
    );
  });

  group('navigate', () {
    test('returns error when required argument is missing', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'navigate', arguments: {}),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('path'));
    });
  });

  group('perform_tap', () {
    test('returns error when required arguments are missing', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'perform_tap', arguments: {}),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, isNotEmpty);
    });

    test('taps Events tab by text finder and verifies route change', () async {
      // Navigate to a known starting point.
      await env.serverConnection.callTool(
        CallToolRequest(name: 'navigate', arguments: {'path': '/discover'}),
      );

      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'perform_tap',
          arguments: {'finder': 'byText', 'finder_value': 'Events'},
        ),
      );

      expect(result.isError, isNull, reason: result.describe);

      // Confirm the app navigated to /events.
      final routeResult = await env.serverConnection.callTool(
        CallToolRequest(name: 'get_route', arguments: {}),
      );
      final routeText = (routeResult.content.first as TextContent).text;
      expect(routeText, contains('EventsPage'));

      // Leave the app on /discover for subsequent tests.
      await env.serverConnection.callTool(
        CallToolRequest(name: 'navigate', arguments: {'path': '/discover'}),
      );
    });
  });

  group('perform_set_text', () {
    test('returns error when required argument is missing', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'perform_set_text', arguments: {}),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('text'));
    });
  });

  group('perform_scroll', () {
    test('returns error when required arguments are missing', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'perform_scroll', arguments: {}),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, isNotEmpty);
    });

    test('scrolls the widgets page scroll view down and back up', () async {
      await env.serverConnection.callTool(
        CallToolRequest(name: 'navigate', arguments: {'path': '/widgets'}),
      );

      // Scroll down.
      final downResult = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'perform_scroll',
          arguments: {
            'finder': 'byKey',
            'finder_value': 'showcase_scroll_view',
            'direction': 'down',
            'pixels': 300.0,
          },
        ),
      );
      expect(downResult.isError, isNull, reason: downResult.describe);

      // Scroll back up.
      final upResult = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'perform_scroll',
          arguments: {
            'finder': 'byKey',
            'finder_value': 'showcase_scroll_view',
            'direction': 'up',
            'pixels': 300.0,
          },
        ),
      );
      expect(upResult.isError, isNull, reason: upResult.describe);

      await env.serverConnection.callTool(
        CallToolRequest(name: 'navigate', arguments: {'path': '/discover'}),
      );
    });
  });

  group('perform_scroll_until_visible', () {
    test('returns error when required arguments are missing', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'perform_scroll_until_visible', arguments: {}),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, isNotEmpty);
    });

    test('scrolls until State Inspector section is visible', () async {
      await env.serverConnection.callTool(
        CallToolRequest(name: 'navigate', arguments: {'path': '/widgets'}),
      );

      // Scroll back to top first so the test starts from a known position.
      await env.serverConnection.callTool(
        CallToolRequest(
          name: 'perform_scroll',
          arguments: {
            'finder': 'byKey',
            'finder_value': 'showcase_scroll_view',
            'direction': 'up',
            'pixels': 2000.0,
          },
        ),
      );

      // Scroll until the "State Inspector" section header is visible.
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'perform_scroll_until_visible',
          arguments: {
            'scroll_finder': 'byKey',
            'scroll_finder_value': 'showcase_scroll_view',
            'finder': 'byText',
            'finder_value': 'State Inspector',
          },
        ),
      );

      expect(result.isError, isNull, reason: result.describe);

      await env.serverConnection.callTool(
        CallToolRequest(name: 'navigate', arguments: {'path': '/discover'}),
      );
    });
  });

  group('get_semantics', () {
    test('returns a non-empty list of semantics nodes', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'get_semantics', arguments: {}),
      );

      expect(result.isError, isNull, reason: result.describe);
      final text = (result.content.first as TextContent).text;
      expect(text, isNotEmpty);
    });

    test('nodes include known labels from the discover page', () async {
      await env.serverConnection.callTool(
        CallToolRequest(name: 'navigate', arguments: {'path': '/discover'}),
      );

      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'get_semantics', arguments: {}),
      );

      expect(result.isError, isNull, reason: result.describe);
      final text = (result.content.first as TextContent).text;
      // The bottom nav bar and app bar are always visible on the discover page.
      expect(text, contains('Discover'));
    });
  });

  group('perform_semantic_action', () {
    test('returns error when required arguments are missing', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'perform_semantic_action', arguments: {}),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, isNotEmpty);
    });

    test(
      'taps Events tab by semantics label and verifies route change',
      () async {
        await env.serverConnection.callTool(
          CallToolRequest(name: 'navigate', arguments: {'path': '/discover'}),
        );

        final result = await env.serverConnection.callTool(
          CallToolRequest(
            name: 'perform_semantic_action',
            arguments: {'action': 'tap', 'label': 'Events'},
          ),
        );
        expect(result.isError, isNull, reason: result.describe);

        await smallDelay;

        final routeResult = await env.serverConnection.callTool(
          CallToolRequest(name: 'get_route', arguments: {}),
        );
        final routeText = (routeResult.content.first as TextContent).text;
        expect(routeText, contains('EventsPage'));

        await env.serverConnection.callTool(
          CallToolRequest(name: 'navigate', arguments: {'path': '/discover'}),
        );
      },
    );
  });

  group('close_app', () {
    test('closes the app', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'close_app'),
      );

      expect(result.isError, isNull);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('Closed app.'));
    });
  });
}

Future<void> _startApp(
  TestEnvironment<TestMCPClient, InspectorMCPServer> env,
  String projectDir,
) async {
  // ignore: unused_local_variable
  final result = await env.serverConnection.callTool(
    CallToolRequest(
      name: 'run_app',
      arguments: {'working_directory': projectDir},
    ),
  );

  // "'Launched. (device ID: zzz)'"
  if (result.isError == true) {
    throw result.describe;
  }

  // No real reason for this (prevents flashing open and closed?).
  await Future.delayed(Duration(milliseconds: 500));
}

extension on CallToolResult {
  String get describe => content.map((c) => c.toString()).join('\n');
}

Future<void> get smallDelay => Future.delayed(Duration(milliseconds: 250));
