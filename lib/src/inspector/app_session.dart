import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'diagnostics_node.dart';
import 'error_summarizers.dart';
import 'flutter_service_extensions.dart';
import '../utils.dart';

/// Manages a `flutter run --machine` subprocess.
///
/// Use [AppSession.start] to launch a Flutter app and obtain a session.
/// The session provides [events] for monitoring app lifecycle and output,
/// [restart] for hot reload/restart, [stop] to terminate the app, and
/// [serviceExtensions] for direct access to Flutter VM service extensions.
class AppSession {
  AppSession._(this._process, this._eventListener, {this.deviceId}) {
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

  /// The 'flutter run' device ID that we launched on.
  final String? deviceId;

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
  /// When [deviceId] is omitted, auto-selects the best available device
  /// (preferring desktop, then simulators/emulators, then physical devices).
  ///
  /// Throws a [DaemonException] if the process exits before the app starts
  /// or if no suitable device can be found.
  static Future<AppSession> start({
    required String workingDirectory,
    required EventCallback eventListener,
    String? deviceId,
    String? target,
  }) async {
    deviceId ??= await _autoSelectDevice(workingDirectory);

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

    final AppSession session = AppSession._(
      process,
      eventListener,
      deviceId: deviceId,
    );
    await session._startedCompleter.future;
    return session;
  }

  /// Runs `flutter devices --machine` and returns the best device ID for the
  /// given project, or null if no devices are found.
  ///
  /// Preference order: desktop (host OS) > iOS Simulator > Android emulator >
  /// physical device. Web and cross-compile desktop are skipped. Each candidate
  /// is checked for platform support (e.g. a `macos/` folder must exist).
  static Future<String?> _autoSelectDevice(String workingDirectory) async {
    final List<Map<String, dynamic>> devices;
    try {
      devices = await _getDevices();
    } on DaemonException {
      // Fail open — let `flutter run` pick a device itself.
      return null;
    }

    if (devices.isEmpty) return null;

    // Map targetPlatform (from `flutter devices --machine`) to the project
    // platform folder name. Note: devices report 'darwin' but the folder and
    // `flutter create --platforms=` flag use 'macos'.
    const Map<String, String> platformFolders = {
      'darwin': 'macos',
      'linux': 'linux',
      'windows': 'windows',
      'android': 'android',
      'ios': 'ios',
      'web-javascript': 'web',
    };

    bool projectSupports(String targetPlatform) {
      final String? folder = platformFolders[targetPlatform];
      if (folder == null) {
        // Unknown platform — don't filter.
        return true;
      }
      return Directory(path.join(workingDirectory, folder)).existsSync();
    }

    final String hostPlatform = _hostTargetPlatform();

    // Score each device: lower is better. Null means skip entirely.
    int? devicePriority(Map<String, dynamic> device) {
      final String target = device['targetPlatform'] as String? ?? '';
      final bool isEmulator = device['emulator'] as bool? ?? false;

      // Desktop matching host OS.
      if (target == hostPlatform) return 0;

      // iOS Simulator (running).
      if (target == 'ios' && isEmulator) return 1;

      // Android emulator (running).
      if (target == 'android' && isEmulator) return 2;

      // Physical mobile device.
      if (target == 'ios' || target == 'android') return 3;

      // Skip cross-compile desktop (e.g. linux on macOS) — unlikely to work.
      if (target == 'darwin' || target == 'linux' || target == 'windows') {
        return null;
      }

      // Skip web — inspector and evaluate don't work the same way.
      if (target == 'web-javascript') return null;

      return 4;
    }

    // Filter to supported, non-skipped devices and sort by priority.
    final List<Map<String, dynamic>> candidates =
        devices
            .where(
              (d) =>
                  projectSupports(d['targetPlatform'] as String? ?? '') &&
                  devicePriority(d) != null,
            )
            .toList()
          ..sort((a, b) => devicePriority(a)!.compareTo(devicePriority(b)!));

    if (candidates.isEmpty) {
      final String deviceList = devices
          .map(
            (d) =>
                '  - ${d['name']} (${d['id']}, '
                'platform: ${d['targetPlatform']})',
          )
          .join('\n');
      final String hostPlatformName = _hostPlatformName();
      throw DaemonException(
        'No device matches this project\'s enabled platforms.\n\n'
        'Available devices:\n$deviceList\n\n'
        'To enable desktop, run: '
        'flutter create --platforms=$hostPlatformName .',
      );
    }

    final String selectedId = candidates.first['id'] as String;
    return selectedId;
  }

  /// Returns the `targetPlatform` string for the host OS.
  static String _hostTargetPlatform() {
    if (Platform.isMacOS) return 'darwin';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    return '';
  }

  /// Returns the Flutter platform name for the host OS (used in
  /// `flutter create --platforms=`).
  static String _hostPlatformName() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    return 'macos';
  }

  /// Runs `flutter devices --machine` and returns the parsed JSON list.
  static Future<List<Map<String, dynamic>>> _getDevices() async {
    final ProcessResult result = await Process.run('flutter', [
      'devices',
      '--machine',
    ]);

    if (result.exitCode != 0) {
      throw DaemonException(
        'flutter devices failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }

    final String stdout = result.stdout as String;

    // `flutter devices --machine` may emit non-JSON lines before the JSON
    // array (e.g. "Waiting for another flutter command..."). Find the array.
    final int jsonStart = stdout.indexOf('[');
    if (jsonStart == -1) {
      throw DaemonException('flutter devices returned no JSON output.');
    }

    final Object? decoded = jsonTryParse(stdout.substring(jsonStart));
    if (decoded is! List) {
      throw DaemonException('flutter devices returned unexpected output.');
    }

    return decoded.cast<Map<String, dynamic>>();
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
        if (!_startedCompleter.isCompleted) {
          _startedCompleter.complete();
        }
      } else if (event == 'app.debugPort') {
        _vmServiceUri = params['wsUri'] as String?;
        _connectVmService(_vmServiceUri!);
      } else if (event == 'app.devTools') {
        _devToolsUri = params['uri'] as String?;
      } else if (event == 'app.dtd') {
        _dtdToolsUri = params['uri'] as String?;
      } else if (event == 'app.progress' &&
          params['progressId'] == 'hot.restart' &&
          params['finished'] == true) {
        // Re-bootstrap semantics after hot restart. The daemon sends this event
        // once the new isolate is running and the app has started — the Flutter
        // binding is initialized at this point, so the evaluate calls succeed.

        // TODO: We still seem to be having issues re-enabling semantics.
        _serviceExtensions?.bootstrapSemantics().ignore();
      }

      if (!_sessionEnded) {
        _eventListener(DaemonEvent(event, params));
      }
    }
  }

  Future<void> _connectVmService(String wsUri) async {
    final vmService = await vmServiceConnectUri(wsUri);

    _serviceExtensions = FlutterServiceExtensions(vmService);

    // Bootstrap semantics on initial connect. Best-effort — app.started has
    // fired by the time _connectVmService is called, so the Flutter binding
    // is initialized. The app.progress/hot.restart handler below re-bootstraps
    // after every full restart.
    _serviceExtensions!.bootstrapSemantics().ignore();

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
      } else if (event.extensionKind == 'Flutter.Navigation') {
        final data = event.extensionData?.data;
        final route = data?['route'];
        final description =
            route is Map ? route['description'] as String? : null;
        _eventListener(
          DaemonEvent('flutter.navigation', {
            if (description != null) 'route': description,
          }),
        );
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

    // If the app was running and we didn't initiate the stop ourselves,
    // emit a synthetic app.stop so the server can clean up the session.
    if (!_sessionEnded && _appId != null) {
      _eventListener(DaemonEvent('app.stop', {'appId': _appId}));
    }

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
