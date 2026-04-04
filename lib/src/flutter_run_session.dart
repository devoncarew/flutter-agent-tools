import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service_io.dart';

import 'diagnostics_node.dart';
import 'flutter_service_extensions.dart';

/// An event emitted by a running Flutter app via the `flutter run --machine`
/// daemon protocol.
class FlutterEvent {
  FlutterEvent(this.event, this.params);

  final String event;
  final Map<String, dynamic> params;
}

/// Manages a `flutter run --machine` subprocess.
///
/// Use [FlutterRunSession.start] to launch a Flutter app and obtain a session.
/// The session provides [events] for monitoring app lifecycle and output,
/// [restart] for hot reload/restart, [stop] to terminate the app, and
/// [serviceExtensions] for direct access to Flutter VM service extensions.
class FlutterRunSession {
  FlutterRunSession._(this._process, this._eventListener) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onDone: _handleDone);
    _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_stderrLines.add);
  }

  final Process _process;
  String? _appId;

  final Completer<void> _startedCompleter = Completer<void>();
  final List<String> _stderrLines = [];
  int _nextId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  final EventCallback _eventListener;
  bool _sessionEnded = false;

  String? _vmServiceUri;
  FlutterServiceExtensions? _serviceExtensions;

  // ignore: unused_field
  String? _devToolsUri;

  // ignore: unused_field
  String? _dtdToolsUri;

  /// Access to Flutter VM service extensions for this session.
  ///
  /// Available once the app has started and the VM service has connected
  /// (i.e. after [start] returns). Null if the VM service has not yet
  /// connected or has been disposed.
  FlutterServiceExtensions? get serviceExtensions => _serviceExtensions;

  /// Launches `flutter run --machine` in [workingDirectory] and waits until
  /// the app has fully started.
  ///
  /// Throws a [StateError] if the process exits before the app starts.
  static Future<FlutterRunSession> start({
    required String workingDirectory,
    required EventCallback eventListener,
    String? deviceId,
    String? target,
  }) async {
    final List<String> args = [
      'run',
      '--machine',
      if (deviceId != null) ...['--device-id', deviceId],
      if (target != null) ...['--target', target],
    ];

    final Process process = await Process.start(
      'flutter',
      args,
      workingDirectory: workingDirectory,
    );

    final FlutterRunSession session = FlutterRunSession._(
      process,
      eventListener,
    );
    await session._startedCompleter.future;
    return session;
  }

  /// Hot reloads the app. If [fullRestart] is true, performs a hot restart
  /// instead.
  Future<void> restart({bool fullRestart = false}) async {
    final String appId = _appId!;
    final Map<String, dynamic> result = await _sendCommand('app.restart', {
      'appId': appId,
      'fullRestart': fullRestart,
    });
    final int code = (result['code'] as num?)?.toInt() ?? 0;
    if (code != 0) {
      final String message = result['message'] as String? ?? 'unknown error';
      throw StateError('app.restart failed (code $code): $message');
    }
  }

  /// Stops the running app.
  Future<void> stop() async {
    await _sendCommand('app.stop', {'appId': _appId!});
  }

  /// Takes a screenshot of the root widget, returning base64-encoded PNG data.
  ///
  /// The root widget's object id and logical size are resolved automatically
  /// via the inspector protocol. [maxPixelRatio] scales the output resolution.
  Future<String> takeScreenshot({double maxPixelRatio = 1.0}) async {
    final FlutterServiceExtensions extensions = _serviceExtensions!;

    // getRootWidget returns full detail including valueId — the inspector object
    // handle required by the screenshot extension.
    final DiagnosticsNode rootNode = await extensions.getRootWidget();
    final String? rootId = rootNode.valueId;
    if (rootId == null) {
      throw StateError('getRootWidget did not return a valueId');
    }

    final (double width, double height) = await _getWidgetSize(
      extensions,
      rootId,
    );

    final String? base64Data = await extensions.screenshot(
      id: rootId,
      width: width,
      height: height,
      maxPixelRatio: maxPixelRatio,
    );
    if (base64Data == null) {
      throw StateError(
        'Screenshot returned null — widget may not be on screen',
      );
    }
    return base64Data;
  }

  /// Returns the logical size of the widget with [id] by examining its details
  /// subtree properties. Looks for a `Size(w, h)` pattern in property
  /// descriptions, which is how Flutter's RenderObject.size surfaces in the
  /// diagnostics tree. Falls back to 400x800 if the size cannot be determined.
  Future<(double, double)> _getWidgetSize(
    FlutterServiceExtensions extensions,
    String diagnosticableId,
  ) async {
    try {
      final DiagnosticsNode node = await extensions.getDetailsSubtree(
        diagnosticableId,
        subtreeDepth: 2,
      );
      final (double, double)? size = _extractSize(node);
      if (size != null) return size;
    } catch (_) {
      // Fall through to default.
    }
    return (400.0, 800.0);
  }

  /// Recursively searches [node] and its properties for a `Size(w, h)` value.
  (double, double)? _extractSize(DiagnosticsNode node) {
    final RegExpMatch? match = RegExp(
      r'Size\((\d+\.?\d*),\s*(\d+\.?\d*)\)',
    ).firstMatch(node.description);
    if (match != null) {
      return (double.parse(match.group(1)!), double.parse(match.group(2)!));
    }
    for (final DiagnosticsNode prop in node.properties) {
      final (double, double)? result = _extractSize(prop);
      if (result != null) return result;
    }
    return null;
  }

  Future<Map<String, dynamic>> _sendCommand(
    String method,
    Map<String, dynamic> params,
  ) {
    final int id = _nextId++;
    final Completer<Map<String, dynamic>> completer =
        Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final String message =
        '[${jsonEncode({'id': id, 'method': method, 'params': params})}]';
    _process.stdin.writeln(message);
    return completer.future;
  }

  void _handleLine(String line) {
    // Daemon messages are wrapped in [ ]; ignore stray output (build logs, etc).
    final String trimmed = line.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) {
      // Convert regular stdio output to log messages.
      if (!_sessionEnded) {
        _eventListener(
          FlutterEvent('app.log', {'appId': _appId, 'log': trimmed}),
        );
      }
      return;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return;
    }

    if (decoded is! List || decoded.isEmpty) return;
    final Object? msg = decoded.first;
    if (msg is! Map<String, dynamic>) return;

    if (msg.containsKey('id')) {
      // Response to a command we sent.
      final int id = msg['id'] as int;
      final Completer<Map<String, dynamic>>? completer = _pending.remove(id);
      if (completer != null) {
        final Object? error = msg['error'];
        if (error != null) {
          final String errorMsg =
              error is Map
                  ? (error['message'] as String? ?? '$error')
                  : '$error';
          completer.completeError(StateError(errorMsg));
        } else {
          final Object? result = msg['result'];
          completer.complete(
            result is Map<String, dynamic> ? result : <String, dynamic>{},
          );
        }
      }
    } else if (msg.containsKey('event')) {
      // Unsolicited event from the daemon.
      final String event = msg['event'] as String;
      final Map<String, dynamic> params =
          (msg['params'] as Map<String, dynamic>?) ?? <String, dynamic>{};

      if (event == 'app.start') {
        _appId = params['appId'] as String?;
      } else if (event == 'app.started') {
        if (!_startedCompleter.isCompleted) _startedCompleter.complete();
      } else if (event == 'app.debugPort') {
        _vmServiceUri = params['wsUri'] as String?;
        _connectVmService(_vmServiceUri!);
      } else if (event == 'app.devTools') {
        _devToolsUri = params['uri'] as String?;
      } else if (event == 'app.dtd') {
        _dtdToolsUri = params['uri'] as String?;
      }

      if (!_sessionEnded) {
        _eventListener(FlutterEvent(event, params));
      }
    }
  }

  Future<void> _connectVmService(String wsUri) async {
    final vmService = await vmServiceConnectUri(wsUri);
    _serviceExtensions = FlutterServiceExtensions(vmService);
  }

  void _handleDone() {
    // Process stdout closed — the subprocess exited.
    if (!_startedCompleter.isCompleted) {
      final String stderr = _stderrLines.join('\n');
      _startedCompleter.completeError(
        StateError('flutter run exited before app started.\n$stderr'),
      );
    }
    for (final Completer<Map<String, dynamic>> c in _pending.values) {
      c.completeError(StateError('flutter run process exited'));
    }
    _pending.clear();

    _sessionEnded = true;

    _serviceExtensions?.dispose();
    _serviceExtensions = null;
  }
}

typedef EventCallback = void Function(FlutterEvent);
