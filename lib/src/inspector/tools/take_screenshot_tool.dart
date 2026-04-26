import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../../utils.dart';
import '../tool_context.dart';

/// Implements the `take_screenshot` MCP tool.
///
/// Captures a PNG screenshot of the running Flutter app.
class TakeScreenshotTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'take_screenshot',
    description: '''
Captures a PNG screenshot of the running Flutter app.

Flutter-rendered view only — native system UI (dialogs, share sheets) will not
appear. If a red "flutter.error" chip is visible, call get_output to clear it
first (the chip disappears once errors are acknowledged).''',
    inputSchema: Schema.object(
      properties: {
        'pixel_ratio': Schema.num(
          description:
              'Device pixel ratio. Higher values produce sharper '
              'images. Defaults to 1.0.',
        ),
      },
      required: [],
    ),
  );

  @override
  Future<CallToolResult> handle(
    CallToolRequest request,
    ToolContext context,
  ) async {
    final session = context.activeSession;
    if (session == null) return context.noActiveSession();

    context.validateParams(request, definition.inputSchema.required!);
    final pixelRatio = coerceDouble(request.arguments?['pixel_ratio']);

    final extensions = session.serviceExtensions;
    bool overlaysDisabled = false;
    try {
      if (session.hasCompanion) {
        await extensions!.slipstreamOverlays(enabled: false);
        overlaysDisabled = true;
      }
      final String base64Data = await session.takeScreenshot(
        maxPixelRatio: pixelRatio,
      );
      if (session.hasCompanion) {
        overlaysDisabled = false;
        await extensions!.slipstreamOverlays(enabled: true);
        extensions.slipstreamLog(
          'screenshot',
          kind: 'screenshot',
          viz: 'flash',
        );
      }
      return CallToolResult(
        content: [ImageContent(data: base64Data, mimeType: 'image/png')],
      );
    } on RPCError catch (e) {
      // Restore overlays even on failure.
      if (overlaysDisabled) {
        extensions!.slipstreamOverlays(enabled: true).ignore();
      }
      return context.rpcError(e);
    }
  }
}
