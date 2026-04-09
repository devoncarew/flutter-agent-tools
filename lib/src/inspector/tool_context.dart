import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

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
  ToolContext({required Map<String, AppSession> sessions, required this.log})
    : _sessions = sessions;

  final Map<String, AppSession> _sessions;

  /// Logs a message at the given level to the MCP client.
  final void Function(LoggingLevel level, String message) log;

  /// Returns the session for [sessionId], or null if not found.
  AppSession? session(String? sessionId) => _sessions[sessionId];

  /// Removes and returns the session for [sessionId], or null if not found.
  AppSession? removeSession(String? sessionId) => _sessions.remove(sessionId);

  /// Returns an error result indicating no session was found for [sessionId].
  CallToolResult unknownSession(String? sessionId) {
    return CallToolResult(
      isError: true,
      content: [TextContent(text: 'No session found for ID: $sessionId')],
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
