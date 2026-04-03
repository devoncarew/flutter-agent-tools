import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  FlutterRunSession._(this._process) {
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
  final StreamController<FlutterEvent> _eventController =
      StreamController<FlutterEvent>.broadcast();
  final List<String> _stderrLines = [];
  int _nextId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  /// Events emitted by the running Flutter app.
  Stream<FlutterEvent> get events => _eventController.stream;

  /// Launches `flutter run --machine` in [workingDirectory] and waits until
  /// the app has fully started.
  ///
  /// Throws a [StateError] if the process exits before the app starts.
  static Future<FlutterRunSession> start({
    required String workingDirectory,
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

    final FlutterRunSession session = FlutterRunSession._(process);
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
      if (!_eventController.isClosed) {
        // The params field will be a map with the fields appId and log.
        _eventController.add(
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
      }

      // TODO: listen for app.debugPort and read out the wsUri (vm service
      // protocol) field

      if (!_eventController.isClosed) {
        _eventController.add(FlutterEvent(event, params));
      }
    }
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
    if (!_eventController.isClosed) _eventController.close();
  }
}
