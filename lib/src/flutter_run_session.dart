import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

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
/// [restart] for hot reload/restart, and [stop] to terminate the app.
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
  VmService? _vmService;

  // ignore: unused_field
  String? _devToolsUri;

  // ignore: unused_field
  String? _dtdToolsUri;

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

  /// Returns whether debug paint is currently enabled.
  Future<bool> getDebugPaint() async {
    final Response response = await _callExtension('ext.flutter.debugPaint');
    return response.json!['enabled'] == 'true';
  }

  /// Enables or disables debug paint (layout debug lines overlay).
  Future<void> setDebugPaint(bool enabled) async {
    await _callExtension(
      'ext.flutter.debugPaint',
      args: {'enabled': enabled.toString()},
    );
  }

  // ---------------------------------------------------------------------------
  // Flutter Inspector
  // If inspector-related methods grow significantly, consider extracting them
  // to a dedicated FlutterInspector class backed by the VmService connection.

  /// Returns the root widget as a [DiagnosticsNode] JSON tree.
  ///
  /// Each node contains:
  ///   - `description`: human-readable widget description
  ///   - `widgetRuntimeType`: the widget class name
  ///   - `children`: list of child nodes (same structure, recursively)
  ///   - `shouldIndent`: display hint
  ///
  /// [groupName] is used by the inspector for object lifetime management.
  Future<Map<String, dynamic>> getRootWidget({
    String objectGroup = 'flutter_agent_tools',
  }) async {
    final Response response = await _callExtension(
      'ext.flutter.inspector.getRootWidget',
      args: {'objectGroup': objectGroup, 'isSummaryTree': 'true'},
    );
    return response.json!;
  }

  /// Calls a VM service extension on the first isolate that has it registered.
  ///
  /// Throws a [StateError] if no isolate has the extension registered.
  Future<Response> _callExtension(
    String method, {
    Map<String, dynamic>? args,
  }) async {
    final VmService vmService = _vmService!;
    final String isolateId = await _isolateIdForExtension(method);
    return vmService.callServiceExtension(
      method,
      isolateId: isolateId,
      args: args,
    );
  }

  /// Returns the isolate ID of the first isolate that has [extension] registered.
  ///
  /// TODO: Optimize this — currently it calls getVM() and getIsolate() on every
  /// invocation. We should cache the isolate ID (keyed by extension) and
  /// invalidate the cache on hot restart. To do that correctly we'll need to
  /// listen to VM service events (e.g. IsolateStart / IsolateExit, or the
  /// Extension event) so we know when isolates change and re-register their
  /// extensions after a hot restart.
  Future<String> _isolateIdForExtension(String extension) async {
    final VmService vmService = _vmService!;
    final VM vm = await vmService.getVM();
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Isolate isolate = await vmService.getIsolate(ref.id!);
      if (isolate.extensionRPCs?.contains(extension) == true) {
        return ref.id!;
      }
    }
    throw StateError('No isolate found with extension: $extension');
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
        // The params field will be a map with the fields appId and log.
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
    _vmService = await vmServiceConnectUri(wsUri);
  }

  /// Returns the VM service extension RPCs registered across all live isolates.
  Future<List<String>> listServiceExtensions() async {
    final VmService vmService = _vmService!;
    final VM vm = await vmService.getVM();
    final List<String> extensions = [];
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Isolate isolate = await vmService.getIsolate(ref.id!);
      extensions.addAll(isolate.extensionRPCs ?? []);
    }
    extensions.sort();
    return extensions;
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

    _vmService?.dispose();
    _vmService = null;
  }
}

typedef EventCallback = void Function(FlutterEvent);
