import 'dart:async';
import 'dart:math';

import 'package:dart_mcp/server.dart';
import 'package:unique_names_generator/unique_names_generator.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import 'flutter_run_session.dart';
import 'layout_formatter.dart';
import 'route_formatter.dart';
import 'utils.dart';

/// The MCP server for flutter-agent-tools.
base class FlutterAgentServer extends MCPServer
    with ToolsSupport, LoggingSupport {
  FlutterAgentServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'flutter-agent-tools',
          version: '0.1.0',
        ),
        instructions:
            'Tools for AI agents working on Dart and Flutter projects.',
      ) {
    loggingLevel = LoggingLevel.info;

    registerTool(flutterLaunchAppTool, _flutterLaunchApp);
    registerTool(flutterReloadTool, _flutterReload);
    registerTool(flutterTakeScreenshotTool, _flutterTakeScreenshot);
    registerTool(flutterInspectLayoutTool, _flutterInspectLayout);
    registerTool(flutterEvaluateTool, _flutterEvaluate);
    registerTool(flutterQueryUiTool, _flutterQueryUi);
    registerTool(flutterCloseAppTool, _flutterCloseApp);
  }

  final Map<String, FlutterRunSession> _sessions = {};
  final Map<String, StreamSubscription<DaemonEvent>> _subscriptions = {};

  @override
  Future<void> shutdown() async {
    await Future.wait(_subscriptions.values.map((s) => s.cancel()));
    _subscriptions.clear();
    await Future.wait(_sessions.values.map((session) => session.stop()));
    _sessions.clear();
    await super.shutdown();
  }

  final Random _random = Random();
  final UniqueNamesGenerator _nameGenerator = UniqueNamesGenerator(
    config: Config(
      length: 2,
      dictionaries: [adjectives, animals],
      separator: '_',
    ),
  );

  String _newSessionId() {
    final String suffix =
        List.generate(
          2,
          (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();

    return [_nameGenerator.generate(), suffix].join('_');
  }

  final Tool flutterLaunchAppTool = Tool(
    name: 'flutter_launch_app',
    description:
        'Builds and launches the Flutter app. Returns a session ID required '
        'by all other flutter_* tools. Call this first before inspecting, '
        'screenshotting, or evaluating. Flutter.Error events from the running '
        'app are automatically forwarded as MCP log warnings — no polling needed.',
    inputSchema: Schema.object(
      properties: {
        'working_directory': Schema.string(
          description: 'The Flutter project directory to launch.',
        ),
        'target': Schema.string(
          description:
              'The main entry point to launch (e.g. lib/main.dart). '
              'Defaults to the project default.',
        ),
        'device': Schema.string(
          description:
              'Optional device ID override. When omitted, auto-selects the '
              'best available device (prefers desktop for fast builds). Only '
              'pass this if the user requests a specific device.',
        ),
      },
      required: ['working_directory'],
    ),
  );

  Future<CallToolResult> _flutterLaunchApp(CallToolRequest request) async {
    final Map<String, dynamic> args = request.arguments!;
    final String workingDirectory = args['working_directory'] as String;
    final String? device = args['device'] as String?;
    final String? target = args['target'] as String?;

    final String sessionId = _newSessionId();

    final FlutterRunSession session;
    try {
      session = await FlutterRunSession.start(
        workingDirectory: workingDirectory,
        eventListener: (event) => _handleEvent(sessionId, event),
        deviceId: device,
        target: target,
        debugLogger: (msg) {
          debugLog(msg);
        },
      );
    } on DaemonException catch (e) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: e.message)],
      );
    }

    _sessions[sessionId] = session;

    final String deviceInfo =
        session.deviceId != null ? 'Device ID: ${session.deviceId}, ' : '';
    return CallToolResult(
      content: [
        TextContent(text: 'Launched. ${deviceInfo}Session ID: $sessionId'),
      ],
    );
  }

  static const String _loggerId = 'flutter_agent_tools';

  void _handleEvent(String sessionId, DaemonEvent event) {
    if (event.event == 'app.stop') {
      _releaseSession(sessionId);

      this.log(
        LoggingLevel.info,
        '[$sessionId] App stopped; session released.',
        logger: _loggerId,
      );

      return;
    } else if (event.event == 'flutter.error') {
      final String summary =
          event.params['summary'] as String? ?? 'Unknown Flutter error';
      this.log(
        LoggingLevel.warning,
        '[flutter.error] $summary',
        logger: _loggerId,
      );
      return;
    }

    final item = _convertToLog(event);
    if (item != null) {
      if (event.event == 'app.log') {
        // We special case stdio output a bit.
        const appOutputPrefix = 'flutter: ';

        if (item.$2.startsWith(appOutputPrefix)) {
          final msg = item.$2.substring(appOutputPrefix.length);
          this.log(item.$1, '[app] $msg', logger: _loggerId);
        } else {
          // It's system output or stdout / stderr.
          this.log(item.$1, '[stdout] ${item.$2}', logger: _loggerId);
        }
      } else {
        this.log(item.$1, '[${event.event}] ${item.$2}', logger: _loggerId);
      }
    }
  }

  void debugLog(String message) {
    this.log(LoggingLevel.info, '[debug] $message', logger: _loggerId);
  }

  void _releaseSession(String sessionId) {
    _sessions.remove(sessionId);
    _subscriptions.remove(sessionId)?.cancel();
  }

  final Tool flutterCloseAppTool = Tool(
    name: 'flutter_close_app',
    description: 'Stops a running Flutter app and releases its session.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by flutter_launch_app.',
        ),
      },
      required: ['session_id'],
    ),
  );

  final Tool flutterReloadTool = Tool(
    name: 'flutter_reload',
    description:
        'Applies source file changes to a running Flutter app. Call this '
        'after editing Dart files, before taking a screenshot or inspecting '
        'layout. Prefer hot reload for iterative changes; use hot restart '
        '(full_restart: true) when state needs to be fully reset.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by flutter_launch_app.',
        ),
        'full_restart': Schema.bool(
          description:
              'If true, performs a hot restart instead of a hot reload. '
              'Defaults to false.',
        ),
      },
      required: ['session_id'],
    ),
  );

  Future<CallToolResult> _flutterReload(CallToolRequest request) async {
    final String? sessionId = request.arguments!['session_id'] as String?;
    final FlutterRunSession? session = _sessions[sessionId];
    if (sessionId == null || session == null) {
      return _unknownSessionResult(sessionId);
    }

    final bool fullRestart =
        request.arguments!['full_restart'] as bool? ?? false;
    try {
      await session.restart(fullRestart: fullRestart);
    } on DaemonException catch (e) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: e.message)],
      );
    }

    final String action = fullRestart ? 'Hot restart' : 'Hot reload';
    return CallToolResult(content: [TextContent(text: '$action complete.')]);
  }

  Future<CallToolResult> _flutterCloseApp(CallToolRequest request) async {
    final String? sessionId = request.arguments!['session_id'] as String?;
    final FlutterRunSession? session = _sessions.remove(sessionId);
    if (sessionId == null || session == null) {
      return _unknownSessionResult(sessionId);
    }

    _releaseSession(sessionId);

    // We don't await this call.
    session.stop();

    return CallToolResult(content: [TextContent(text: 'App stopped.')]);
  }

  final Tool flutterTakeScreenshotTool = Tool(
    name: 'flutter_take_screenshot',
    description:
        'Captures a PNG screenshot of the running Flutter app. Use '
        'proactively after a reload to visually confirm UI changes are '
        'correct, and when diagnosing layout or rendering issues. '
        'Root widget bounds are resolved automatically.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by flutter_launch_app.',
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

  Future<CallToolResult> _flutterTakeScreenshot(CallToolRequest request) async {
    final String? sessionId = request.arguments!['session_id'] as String?;
    final FlutterRunSession? session = _sessions[sessionId];

    if (sessionId == null || session == null) {
      return _unknownSessionResult(sessionId);
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
      return _rpcErrorResult(e);
    }
  }

  final Tool flutterInspectLayoutTool = Tool(
    name: 'flutter_inspect_layout',
    description:
        'Use when debugging layout issues, overflow errors, or unexpected '
        'widget sizing. Returns constraints, size, flex parameters, and '
        'children for a widget. Omit widget_id to start from the root. '
        'Widget IDs are included in flutter.error log events and in the '
        'output of prior inspect calls — use them to drill into a specific '
        'node. Increase subtree_depth to see deeper child layout.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by flutter_launch_app.',
        ),
        'widget_id': Schema.string(
          description:
              'The widget ID to inspect. Omit to start from the root widget.',
        ),
        'subtree_depth': Schema.int(
          description: 'How many levels of children to include. Defaults to 1.',
        ),
      },
      required: ['session_id'],
    ),
  );

  Future<CallToolResult> _flutterInspectLayout(CallToolRequest request) async {
    final String? sessionId = request.arguments!['session_id'] as String?;
    final FlutterRunSession? session = _sessions[sessionId];
    if (sessionId == null || session == null) {
      return _unknownSessionResult(sessionId);
    }

    final String? widgetId = request.arguments!['widget_id'] as String?;
    final int subtreeDepth = (request.arguments!['subtree_depth'] as int?) ?? 1;

    try {
      final extensions = session.serviceExtensions!;
      final String resolvedId;
      if (widgetId != null) {
        resolvedId = widgetId;
      } else {
        final root = await extensions.getRootWidget();
        if (root.valueId == null) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Root widget has no valueId.')],
          );
        }
        resolvedId = root.valueId!;
      }
      final node = await extensions.getDetailsSubtree(
        resolvedId,
        subtreeDepth: subtreeDepth,
      );
      final layoutSummary = formatLayoutDetails(node, maxDepth: subtreeDepth);
      return CallToolResult(content: [TextContent(text: layoutSummary)]);
    } on RPCError catch (e) {
      return _rpcErrorResult(e);
    }
  }

  final Tool flutterEvaluateTool = Tool(
    name: 'flutter_evaluate',
    description:
        'Evaluates a Dart expression on the running app\'s main isolate and '
        'returns the result as a string. Use for binding-layer and '
        'platform-layer state not visible in the widget tree: FlutterView '
        'properties (physicalSize, devicePixelRatio), MediaQueryData, '
        'Navigator state, or any runtime value. Runs in the root library '
        'scope, so top-level declarations and globals are in scope. '
        'Example: "WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio.toString()"',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by flutter_launch_app.',
        ),
        'expression': Schema.string(
          description:
              'The Dart expression to evaluate. Must produce a value with a '
              'useful toString(). Example: '
              '"WidgetsBinding.instance.platformDispatcher'
              '.views.first.devicePixelRatio.toString()"',
        ),
      },
      required: ['session_id', 'expression'],
    ),
  );

  Future<CallToolResult> _flutterEvaluate(CallToolRequest request) async {
    final String? sessionId = request.arguments!['session_id'] as String?;
    final FlutterRunSession? session = _sessions[sessionId];
    if (sessionId == null || session == null) {
      return _unknownSessionResult(sessionId);
    }

    final String expression = request.arguments!['expression'] as String;
    try {
      final String result = await session.serviceExtensions!.evaluate(
        expression,
      );
      return CallToolResult(content: [TextContent(text: result)]);
    } on RPCError catch (e) {
      return _rpcErrorResult(e);
    }
  }

  final Tool flutterQueryUiTool = Tool(
    name: 'flutter_query_ui',
    description:
        'Returns a high-level description of what is currently on screen in '
        'the running Flutter app. Use to orient before navigating to a '
        'specific app state, to confirm a change took effect, or to '
        'understand the current route before drilling into layout details. '
        'Modes: '
        '"semantics" — flat list of visible, interactive nodes (labels, '
        'roles, bounding boxes); '
        '"widget_tree" — summary widget tree filtered to user-written widgets; '
        '"route" — current route name and navigator state.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by flutter_launch_app.',
        ),
        'mode': Schema.string(
          description:
              'What to return. One of: "semantics", "widget_tree", "route".',
        ),
      },
      required: ['session_id', 'mode'],
    ),
  );

  Future<CallToolResult> _flutterQueryUi(CallToolRequest request) async {
    final String? sessionId = request.arguments!['session_id'] as String?;
    final FlutterRunSession? session = _sessions[sessionId];
    if (sessionId == null || session == null) {
      return _unknownSessionResult(sessionId);
    }

    final String? mode = request.arguments!['mode'] as String?;
    if (mode == null ||
        !const {'semantics', 'widget_tree', 'route'}.contains(mode)) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text:
                'Invalid mode "$mode". '
                'Must be one of: semantics, widget_tree, route.',
          ),
        ],
      );
    }

    try {
      final extensions = session.serviceExtensions!;
      switch (mode) {
        case 'route':
          final root = await extensions.getRootWidgetTree(
            isSummaryTree: true,
            fullDetails: true,
          );
          return CallToolResult(
            content: [TextContent(text: formatRouteInfo(root))],
          );
        default:
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text: 'flutter_query_ui mode "$mode": not yet implemented.',
              ),
            ],
          );
      }
    } on RPCError catch (e) {
      return _rpcErrorResult(e);
    }
  }

  CallToolResult _unknownSessionResult(String? sessionId) {
    return CallToolResult(
      isError: true,
      content: [TextContent(text: 'No session found for ID: $sessionId')],
    );
  }

  CallToolResult _rpcErrorResult(RPCError e) {
    final error = ServiceError.tryParse(e);
    return CallToolResult(
      isError: true,
      content: [TextContent(text: error?.exception ?? e.message)],
    );
  }

  (LoggingLevel, String)? _convertToLog(DaemonEvent event) {
    final Map<String, dynamic> params = event.params;

    // By default, flatten the map.
    String message = params.keys
        .map((String k) {
          final Object? v = params[k];
          return '$k: ${v is String ? "'$v'" : v}';
        })
        .join(', ');

    switch (event.event) {
      case 'app.log':
        {
          message = params['log'] as String? ?? message;
          final bool isError = params['error'] as bool? ?? false;
          return (isError ? LoggingLevel.warning : LoggingLevel.info, message);
        }
      case 'app.progress':
        {
          // The `progressId` field identifies the app.progress type.
          switch (params['progressId']) {
            case 'devFS.update':
              // Filter all app.progress / devFS.update events.
              return null;
            case 'hot.reload':
              // We get a start and a stop event; filter the first and promote
              // the second. Filter both - the agent doesn't need to know
              // about the first, and they already see a message about the
              // second on stdout:
              //
              //   "[stdout] Reloaded 0 libraries in ..."
              return null;
            case 'hot.restart':
              // Filter both start and stop events for the same reason as
              // above.
              return null;
          }
        }
    }

    return (LoggingLevel.info, message);
  }
}

class ServiceError {
  final String exception;
  final String? stack;

  ServiceError(this.exception, this.stack);

  static ServiceError? tryParse(RPCError error) {
    // While highly unusual, when present, `data['details']` is an
    // `{exception, stack}` map, encoded as a JSON string.
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
