// Integration tests for the 'inspector' MCP server.

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:flutter_slipstream/src/inspector/inspector_mcp.dart';
import 'package:test/test.dart';

import '../test/test_utils.dart';

// These tests start a real InspectorMCPServer and exercise its tools from the
// perspective of an MCP client.
//
// A single server instance is shared across all tests in this file.
//
// For the moment this script is run manually.

// TODO: complete the test coverage for the commands

void main(List<String> args) {
  // Require the app to run as the first arg.
  if (args.length != 1) {
    print(
      'usage: dart tool/inspector_integration_test.dart <path-to-flutter-app>',
    );
    exit(1);
  }

  late TestEnvironment<TestMCPClient, InspectorMCPServer> env;
  late String sessionId;

  setUpAll(() async {
    env = TestEnvironment(TestMCPClient(), InspectorMCPServer.new);
    await env.initializeServer();

    final String projectDir = Directory(args[0]).absolute.path;
    sessionId = await _startApp(env, projectDir);
  });

  tearDownAll(() async {
    // TODO: Sombody else is closing the app for us...
    // await env.serverConnection.callTool(
    //   CallToolRequest(name: 'close_app', arguments: {'session_id': sessionId}),
    // );

    await env.shutdown();
  });

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

  // todo: reload

  group('take_screenshot', () {
    test('returns a valid result', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'take_screenshot',
          arguments: {'session_id': sessionId},
        ),
      );

      expect(result.isError, isNull);
      expect(result.content.first, isA<ImageContent>());
    });

    test('returns error when required argument is missing', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'take_screenshot', arguments: {}),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('session_id'));
    });
  });

  // todo: inspect_layout

  // todo: evaluate

  // todo: get_route

  group('navigate', () {
    test('returns error when required argument is missing', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'navigate', arguments: {}),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('session_id'));
      expect(text, contains('path'));
    });
  });

  // todo: get_semantics

  // todo: tap

  group('set_text', () {
    test('returns error when required argument is missing', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'set_text', arguments: {}),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('session_id'));
      expect(text, contains('text'));
    });
  });

  group('close_app', () {
    test('returns error when required argument is missing', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'close_app', arguments: {}),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('session_id'));
    });

    test('closes the app', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'close_app',
          arguments: {'session_id': sessionId},
        ),
      );

      expect(result.isError, isNull);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('App stopped.'));
    });
  });
}

Future<String> _startApp(
  TestEnvironment<TestMCPClient, InspectorMCPServer> env,
  String projectDir,
) async {
  final result = await env.serverConnection.callTool(
    CallToolRequest(
      name: 'run_app',
      arguments: {'working_directory': projectDir},
    ),
  );

  const token = 'Session ID:';

  // "'Launched. Device ID: zzz, Session ID: yyy'"
  final text = (result.content.first as TextContent).text;
  final sessionId = text.substring(text.indexOf(token) + token.length).trim();

  // No real reason for this (prevents flashing open and closed?).
  await Future.delayed(Duration(milliseconds: 500));

  return sessionId;
}
