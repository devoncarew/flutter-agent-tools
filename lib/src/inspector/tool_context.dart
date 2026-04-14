import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../common.dart';
import 'app_session.dart';
import '../utils.dart';

/// A self-contained MCP tool: owns its [Tool] definition and handles
/// [CallToolRequest]s via [handle].
///
/// Implementations live in `lib/src/tools/` one file per tool, named after
/// the MCP command (e.g. `evaluate_tool.dart`). The server registers each tool
/// with:
///
/// ```dart
/// registerTool(tool.definition, (req) => tool.handle(req, _context));
/// ```
abstract class InspectorTool {
  /// The MCP [Tool] definition (name, description, input schema).
  Tool get definition;

  /// Handles a [CallToolRequest], using [context] to access sessions and
  /// shared utilities.
  Future<CallToolResult> handle(CallToolRequest request, ToolContext context);
}

/// Provides tool implementations with access to shared server state.
///
/// Tools receive a [ToolContext] rather than a direct reference to
/// [FlutterAgentServer], keeping them decoupled from the MCP server
/// infrastructure and easier to test independently.
class ToolContext {
  ToolContext({required this.log});

  AppSession? _session;

  /// Logs a message at the given level to the MCP client.
  final void Function(LoggingLevel level, String message) log;

  /// The currently active app session, or null if no app is running.
  AppSession? get activeSession => _session;

  /// Registers [session] as the active session.
  void setSession(AppSession session) {
    _session = session;
  }

  /// Removes and returns the active session, or null if none is running.
  AppSession? removeSession() {
    final s = _session;
    _session = null;
    return s;
  }

  /// Returns an error result indicating no app session is active.
  CallToolResult noActiveSession() {
    return CallToolResult(
      isError: true,
      content: [
        TextContent(
          text:
              'No app is currently running. Call run_app first to launch the '
              'Flutter app.',
        ),
      ],
    );
  }

  /// Returns an error result indicating the slipstream_agent companion package
  /// is not installed. [toolName] is included in the first line for context.
  CallToolResult companionNotInstalled(String toolName) {
    return CallToolResult(
      isError: true,
      content: [
        TextContent(
          text:
              '$toolName: the slipstream_agent companion package is not '
              'installed in this app.\n\n'
              'Add it as a dependency:\n\n'
              '  dependencies:\n'
              '    slipstream_agent: ^0.1.0\n\n'
              'Then call SlipstreamAgent.init() in your main() inside '
              'kDebugMode.\n\n'
              'Alternatively, use perform_semantic_action for '
              'semantics-based interaction without the companion package.',
        ),
      ],
    );
  }

  /// Returns an error result for a VM service [RPCError].
  CallToolResult rpcError(RPCError e) {
    // TODO: We need to double check what we're doing here. Sometimes e.details
    // is populated with information we want to preserve. Should we just be
    // doing
    final details = e.details;
    final error = ServiceError.tryParse(e);
    return CallToolResult(
      isError: true,
      content: [
        TextContent(text: error?.exception ?? e.message),
        if (details != null) TextContent(text: details),
      ],
    );
  }

  /// Validate the required params are present.
  ///
  /// Throws a [ToolException] is a param is missing.
  void validateParams(CallToolRequest request, List<String> requiredParams) {
    final args = request.arguments ?? {};

    final missing =
        requiredParams.where((param) => !args.containsKey(param)).toList();
    if (missing.isNotEmpty) {
      final label = missing.length == 1 ? 'argument' : 'arguments';
      throw ToolException('Missing required $label: ${missing.join(', ')}');
    }
  }
}

/// Parses a structured Dart exception from a VM service [RPCError], when
/// present.
///
/// The VM service encodes Dart exceptions in `error.details` as a JSON string
/// containing `{exception, stack}`. This class extracts that structure so
/// callers can surface the Dart exception message rather than the raw RPC
/// error text.
class ServiceError {
  ServiceError(this.exception, this.stack);

  final String exception;
  final String? stack;

  static ServiceError? tryParse(RPCError error) {
    if (error.details != null) {
      final obj = jsonTryParse(error.details!);
      if (obj is Map) {
        return ServiceError(
          obj['exception'] as String? ?? '',
          obj['stack'] as String?,
        );
      }
    }
    return null;
  }
}
