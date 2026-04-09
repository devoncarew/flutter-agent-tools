// Integration tests for the packages MCP server.
//
// These tests start a real PackagesMCPServer and exercise all three tools
// (package_summary, library_stub, class_stub) from the perspective of an MCP
// client. A single server instance is shared across all tests in this file;
// tests within a file are already serial in Dart's test runner, so no
// additional configuration is needed.

import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:flutter_slipstream/src/shorthand/packages_mcp.dart';
import 'package:test/test.dart';

import '../inspector/test_utils.dart';

// The project root, used as project_directory for all tool calls. Must be
// absolute — the analyzer rejects relative paths.
final String _projectDir = Directory.current.path;

// A package that is a direct dependency of this project and is therefore
// guaranteed to be in the pub cache at a pinned version.
const String _testPackage = 'http';

void main() {
  late TestEnvironment<TestMCPClient, PackagesMCPServer> env;

  setUpAll(() async {
    env = TestEnvironment(TestMCPClient(), PackagesMCPServer.new);
    await env.initializeServer();
  });

  tearDownAll(() async {
    await env.shutdown();
  });

  // ---------------------------------------------------------------------------
  // package_summary

  group('package_summary', () {
    test('returns summary for a known package', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'package_summary',
          arguments: {
            'project_directory': _projectDir,
            'package': _testPackage,
          },
        ),
      );

      expect(result.isError, isNot(isTrue));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('Package: http'));
      expect(text, contains('## Libraries'));
      expect(text, contains('package:http/http.dart'));
    });

    test('returns error for a package not in pub cache', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'package_summary',
          arguments: {
            'project_directory': _projectDir,
            'package': 'no_such_package_xyz_abc',
          },
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('no_such_package_xyz_abc'));
    });

    test('returns error when required argument is missing', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'package_summary',
          arguments: {'project_directory': _projectDir},
          // 'package' intentionally omitted
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('package'));
    });
  });

  // ---------------------------------------------------------------------------
  // library_stub

  group('library_stub', () {
    test('returns stub for a known library', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'library_stub',
          arguments: {
            'project_directory': _projectDir,
            'package': _testPackage,
            'library_uri': 'package:http/http.dart',
          },
        ),
      );

      expect(result.isError, isNot(isTrue));
      final text = (result.content.first as TextContent).text;
      // The stub should be valid-looking Dart with a class or function.
      expect(text, contains('class Client'));
    });

    test('returns error for an unknown library URI', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'library_stub',
          arguments: {
            'project_directory': _projectDir,
            'package': _testPackage,
            'library_uri': 'package:http/no_such_library.dart',
          },
        ),
      );

      expect(result.isError, isTrue);
    });

    test('returns error when required argument is missing', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'library_stub',
          arguments: {
            'project_directory': _projectDir,
            'package': _testPackage,
            // 'library_uri' intentionally omitted
          },
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('library_uri'));
    });
  });

  // ---------------------------------------------------------------------------
  // class_stub

  group('class_stub', () {
    test('returns stub for a known class', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'class_stub',
          arguments: {
            'project_directory': _projectDir,
            'package': _testPackage,
            'library_uri': 'package:http/http.dart',
            'class': 'Client',
          },
        ),
      );

      expect(result.isError, isNot(isTrue));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('class Client'));
      // Should include at least one method signature.
      expect(text, contains('Future'));
    });

    test('returns error for an unknown class name', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'class_stub',
          arguments: {
            'project_directory': _projectDir,
            'package': _testPackage,
            'library_uri': 'package:http/http.dart',
            'class': 'NoSuchClassXyz',
          },
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('NoSuchClassXyz'));
    });

    test('returns error when required argument is missing', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'class_stub',
          arguments: {
            'project_directory': _projectDir,
            'package': _testPackage,
            'library_uri': 'package:http/http.dart',
            // 'class' intentionally omitted
          },
        ),
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('class'));
    });
  });
}
