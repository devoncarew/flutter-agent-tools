import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'diagnostics_node.dart';
import 'error_summarizers.dart';
import 'flutter_service_extensions.dart';

/// Manages a `flutter run --machine` subprocess.
///
/// Use [FlutterRunSession.start] to launch a Flutter app and obtain a session.
/// The session provides [events] for monitoring app lifecycle and output,
/// [restart] for hot reload/restart, [stop] to terminate the app, and
/// [serviceExtensions] for direct access to Flutter VM service extensions.
class FlutterRunSession {
  FlutterRunSession._(this._process, this._eventListener, this.debugLogger) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onDone: _handleDone);
    _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);
  }

  final Process _process;
  String? _appId;

  final Completer<void> _startedCompleter = Completer<void>();
  int _nextId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  final EventCallback _eventListener;
  bool _sessionEnded = false;

  String? _vmServiceUri;
  FlutterServiceExtensions? _serviceExtensions;
  StreamSubscription<Event>? _vmServiceSubscription;

  // Capped at [_maxErrors] most-recent errors; cleared on hot restart.
  static const int _maxErrors = 50;
  final List<FlutterError> _errors = [];

  // ignore: unused_field
  String? _devToolsUri;

  // ignore: unused_field
  String? _dtdToolsUri;

  /// A debug-time only logger; this can send log statements back to the host
  /// MCP client.
  Logger? debugLogger;

  /// Framework errors received via the `Flutter.Error` VM service event since
  /// the session started or the last hot restart.
  List<FlutterError> get errors => List.unmodifiable(_errors);

  /// Access to Flutter VM service extensions for this session.
  ///
  /// Available once the app has started and the VM service has connected
  /// (i.e. after [start] returns). Null if the VM service has not yet
  /// connected or has been disposed.
  FlutterServiceExtensions? get serviceExtensions => _serviceExtensions;

  /// Launches `flutter run --machine` in [workingDirectory] and waits until
  /// the app has fully started.
  ///
  /// Throws a [DaemonException] if the process exits before the app starts.
  static Future<FlutterRunSession> start({
    required String workingDirectory,
    required EventCallback eventListener,
    String? deviceId,
    String? target,
    Logger? debugLogger,
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
      debugLogger,
    );
    await session._startedCompleter.future;
    return session;
  }

  /// Hot reloads the app. If [fullRestart] is true, performs a hot restart
  /// instead.
  ///
  /// Throws a [DaemonException] if there were issues performing the restart.
  Future<void> restart({bool fullRestart = false}) async {
    final String appId = _appId!;
    final Map<String, dynamic> result = await _sendCommand('app.restart', {
      'appId': appId,
      'fullRestart': fullRestart,
    });
    final int code = (result['code'] as num?)?.toInt() ?? 0;
    if (code != 0) {
      final String message = result['message'] as String? ?? 'unknown error';
      throw DaemonException('app.restart failed (code $code): $message');
    }
    _errors.clear();
  }

  /// Stops the running app.
  Future<void> stop() async {
    await _sendCommand('app.stop', {'appId': _appId!});
  }

  /// Takes a screenshot of the root widget, returning base64-encoded PNG data.
  ///
  /// The root widget's object id and size are resolved automatically.
  /// Size is obtained via VM service `evaluate` (exact physical pixels);
  /// falls back to the inspector details subtree if that fails.
  /// [maxPixelRatio] scales the output resolution.
  ///
  /// Throws an [RPCError] if there are issues taking the screenshot.
  Future<String> takeScreenshot({double? maxPixelRatio}) async {
    final FlutterServiceExtensions extensions = _serviceExtensions!;

    // getRootWidget returns full detail including valueId — the inspector
    // object handle required by the screenshot extension.
    final DiagnosticsNode rootNode = await extensions.getRootWidget();
    final String? rootId = rootNode.valueId;
    if (rootId == null) {
      throw rpcError('getRootWidget did not return a valueId');
    }

    var size = await extensions.getPhysicalWindowSize();
    if (size == null) {
      throw rpcError('Could not determine widget size for screenshot');
    }

    final String? base64Data = await extensions.screenshot(
      id: rootId,
      width: size.$1,
      height: size.$2,
      maxPixelRatio: maxPixelRatio,
    );
    if (base64Data == null) {
      throw rpcError('Screenshot returned null — widget may not be on screen');
    }
    return base64Data;
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
    // Daemon messages are wrapped in [ ]; ignore stray output (build logs,
    // etc).
    final String trimmed = line.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) {
      // Convert regular stdio output to log messages.
      if (!_sessionEnded) {
        _eventListener(
          DaemonEvent('app.log', {'appId': _appId, 'log': trimmed}),
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
          completer.completeError(DaemonException(errorMsg));
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
        _eventListener(DaemonEvent(event, params));
      }
    }
  }

  Future<void> _connectVmService(String wsUri) async {
    final vmService = await vmServiceConnectUri(wsUri);
    _serviceExtensions = FlutterServiceExtensions(vmService);

    await vmService.streamListen(EventStreams.kExtension);
    _vmServiceSubscription = vmService.onExtensionEvent.listen((Event event) {
      if (event.extensionKind == 'Flutter.Error') {
        final data = event.extensionData?.data;
        if (data != null) {
          final error = FlutterError.tryParse(data);
          if (error != null) {
            if (_errors.length >= _maxErrors) {
              _errors.removeAt(0);
            }
            _errors.add(error);
            _eventListener(
              DaemonEvent('flutter.error', {
                'summary': compactSummarizer(error),
              }),
            );
          }
        }
      }
    });
  }

  void _handleDone() {
    // Process stdout closed — the subprocess exited.
    if (!_startedCompleter.isCompleted) {
      _startedCompleter.completeError(
        rpcError('flutter run exited before app started.'),
      );
    }
    for (final Completer<Map<String, dynamic>> c in _pending.values) {
      c.completeError(rpcError('flutter run process exited'));
    }
    _pending.clear();

    _sessionEnded = true;

    _vmServiceSubscription?.cancel();
    _vmServiceSubscription = null;
    _serviceExtensions?.dispose();
    _serviceExtensions = null;
  }
}

/// An event emitted by a running Flutter app via the `flutter run --machine`
/// daemon protocol.
class DaemonEvent {
  final String event;
  final Map<String, dynamic> params;

  DaemonEvent(this.event, this.params);
}

/// An error returned from a command sent to 'flutter run' over the daemon
/// protocol.
class DaemonException implements Exception {
  final String message;

  DaemonException(this.message);

  @override
  String toString() => 'DaemonException: $message';
}

/// A Flutter framework error received via the `Flutter.Error` VM service
/// extension event.
class FlutterError {
  FlutterError({required this.node, required this.errorsSinceReload});

  /// The full diagnostic node tree for this error. The root [node.description]
  /// is the generic category (e.g., "Exception caught by rendering library").
  /// The specific error message is the `ErrorSummary` property (level ==
  /// `'summary'`), e.g. "A RenderFlex overflowed by 900 pixels on the bottom".
  final DiagnosticsNode node;

  /// The cumulative error count since the last hot reload, as reported by the
  /// framework (`errorsSinceReload` field).
  final int errorsSinceReload;

  /// Short category label, e.g. "Exception caught by rendering library".
  String get description => node.description;

  /// The specific error message from the `ErrorSummary` property (level ==
  /// `'summary'`), if present. Falls back to [description] otherwise.
  String get detail {
    for (final prop in node.properties) {
      if (prop.level == 'summary' && prop.description.isNotEmpty) {
        return prop.description;
      }
    }
    return description;
  }

  /// A single-line summary combining [description] and [detail].
  String get summary {
    final d = detail;
    return d == description ? description : '$description ▸ $d';
  }

  /// Parses a [FlutterError] from [data], the `extensionData.data` map of a
  /// `Flutter.Error` VM service event. Returns null if the required fields are
  /// absent.
  static FlutterError? tryParse(Map<String, dynamic> data) {
    if (data['description'] == null) return null;
    final int errorsSinceReload =
        (data['errorsSinceReload'] as num?)?.toInt() ?? 0;
    return FlutterError(
      node: DiagnosticsNode.fromJson(data),
      errorsSinceReload: errorsSinceReload,
    );
  }

  @override
  String toString() => 'FlutterError: $summary';
}

typedef EventCallback = void Function(DaemonEvent);

typedef Logger = void Function(String);
