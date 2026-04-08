import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../tool_context.dart';

/// Implements the `take_screenshot` MCP tool.
///
/// Captures a PNG screenshot of the running Flutter app.
class TakeScreenshotTool extends FlutterTool {
  @override
  final Tool definition = Tool(
    name: 'take_screenshot',
    description:
        'Captures a PNG screenshot of the running Flutter app. Use '
        'proactively after a reload to visually confirm UI changes are '
        'correct, and when diagnosing layout or rendering issues. '
        'Root widget bounds are resolved automatically. '
        'Note: only the Flutter view is captured — native system UI such as '
        'platform share sheets, permission dialogs, or OS-level overlays will '
        'not appear in the screenshot even if visible on screen.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by run_app.',
        ),
        'pixel_ratio': Schema.num(
          description:
              'Device pixel ratio for the screenshot. Higher values produce '
              'sharper images. Defaults to 1.0.',
        ),
      },
      required: ['session_id'],
    ),
  );

  @override
  Future<CallToolResult> handle(
    CallToolRequest request,
    ToolContext context,
  ) async {
    final String? sessionId = request.arguments!['session_id'] as String?;
    final session = context.session(sessionId);
    if (sessionId == null || session == null) {
      return context.unknownSession(sessionId);
    }

    final num? pixelRatioArg = request.arguments!['pixel_ratio'] as num?;
    final double? pixelRatio = pixelRatioArg?.toDouble();

    try {
      final String base64Data = await session.takeScreenshot(
        maxPixelRatio: pixelRatio,
      );
      return CallToolResult(
        content: [ImageContent(data: base64Data, mimeType: 'image/png')],
      );
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
