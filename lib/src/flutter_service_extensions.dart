import 'package:vm_service/vm_service.dart';

import 'diagnostics_node.dart';

/// Provides 1:1 access to Flutter VM service extensions.
///
/// Each method maps directly to one `ext.flutter.*` service extension call.
/// Higher-level convenience methods that combine multiple calls belong in
/// [FlutterRunSession] instead.
class FlutterServiceExtensions {
  FlutterServiceExtensions(this._vmService);

  final VmService _vmService;

  // Object group name used for inspector extension calls. The inspector uses
  // groups to manage the lifetime of server-side object references.
  static const String inspectorGroup = 'flutter_agent_tools';

  void dispose() {
    _vmService.dispose();
  }

  // ---------------------------------------------------------------------------
  // VM service (non-extension) helpers

  /// Returns all extension RPCs registered across all live isolates.
  Future<List<String>> listServiceExtensions() async {
    final VM vm = await _vmService.getVM();
    final List<String> extensions = [];
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Isolate isolate = await _vmService.getIsolate(ref.id!);
      extensions.addAll(isolate.extensionRPCs ?? []);
    }
    extensions.sort();
    return extensions;
  }

  // ---------------------------------------------------------------------------
  // ext.flutter.debugPaint

  /// Returns whether the debug paint overlay is currently enabled.
  Future<bool> getDebugPaint() async {
    final Response response = await _callExtension('ext.flutter.debugPaint');
    return response.json!['enabled'] == 'true';
  }

  /// Enables or disables the debug paint overlay (layout debug lines).
  Future<void> setDebugPaint(bool enabled) async {
    await _callExtension(
      'ext.flutter.debugPaint',
      args: {'enabled': enabled.toString()},
    );
  }

  // ---------------------------------------------------------------------------
  // ext.flutter.inspector.*

  /// Returns the root widget as a [DiagnosticsNode] JSON map.
  ///
  /// Returns the root widget node with full detail, including [DiagnosticsNode.valueId]
  /// which is the inspector object handle needed by [screenshot].
  ///
  /// This is a separate implementation from [getRootWidgetTree] and takes no
  /// tree-shape parameters.
  Future<DiagnosticsNode> getRootWidget() async {
    final Response response = await _callExtension(
      'ext.flutter.inspector.getRootWidget',
      args: {'objectGroup': inspectorGroup},
    );
    return DiagnosticsNode.fromJson(_result(response));
  }

  /// Returns the root widget tree, with control over its shape.
  ///
  /// [isSummaryTree] omits lower-level internal widgets (default true).
  /// [withPreviews] includes screenshot thumbnails for each node (default false).
  /// [fullDetails] includes full property detail (default true).
  Future<DiagnosticsNode> getRootWidgetTree({
    bool? isSummaryTree,
    bool? withPreviews,
    bool? fullDetails,
  }) async {
    final Response response = await _callExtension(
      'ext.flutter.inspector.getRootWidgetTree',
      args: {
        'groupName': inspectorGroup,
        if (isSummaryTree != null) 'isSummaryTree': isSummaryTree.toString(),
        if (withPreviews != null) 'withPreviews': withPreviews.toString(),
        if (fullDetails != null) 'fullDetails': fullDetails.toString(),
      },
    );
    return DiagnosticsNode.fromJson(_result(response));
  }

  /// Returns the details subtree for the object with [id].
  ///
  /// The response includes full property detail, including render object sizes.
  ///
  /// [subtreeDepth] will default to 2 if not passed.
  Future<DiagnosticsNode> getDetailsSubtree(
    String diagnosticableId, {
    int? subtreeDepth,
  }) async {
    final Response response = await _callExtension(
      'ext.flutter.inspector.getDetailsSubtree',
      args: {
        'objectGroup': inspectorGroup,
        'arg': diagnosticableId,
        if (subtreeDepth != null) 'subtreeDepth': subtreeDepth.toString(),
      },
    );
    return DiagnosticsNode.fromJson(_result(response));
  }

  // ---------------------------------------------------------------------------
  // ext.flutter.inspector.setSelectionById

  /// Moves the inspector selection to the widget with [id] on the connected
  /// device or emulator.
  ///
  /// This is the same action DevTools performs when you click a widget in the
  /// Widget Tree — it forces the on-screen highlight to move to the widget
  /// without requiring a physical tap.
  ///
  /// Pass `null` for [id] to clear the current selection.
  ///
  /// Returns `true` if the selection was changed.
  Future<bool> setSelectionById(String? id) async {
    final Response response = await _callExtension(
      'ext.flutter.inspector.setSelectionById',
      args: {'arg': id, 'objectGroup': inspectorGroup},
    );
    return response.json!['result'] as bool? ?? false;
  }

  // ---------------------------------------------------------------------------
  // ext.flutter.inspector.screenshot

  /// Takes a screenshot of the object with [id], rendered at [width] × [height]
  /// logical pixels. Returns base64-encoded PNG data, or null if the object is
  /// not currently visible.
  ///
  /// [margin] will default to 0 if not passed.
  /// [maxPixelRatio] will default to 1.0 if not passed.
  /// [debugPaint] will default to false if not passed.
  Future<String?> screenshot({
    required String id,
    required double width,
    required double height,
    double? margin,
    double? maxPixelRatio,
    bool? debugPaint,
  }) async {
    final Response response = await _callExtension(
      'ext.flutter.inspector.screenshot',
      args: {
        'id': id,
        'width': width.toString(),
        'height': height.toString(),
        if (margin != null) 'margin': margin.toString(),
        if (maxPixelRatio != null) 'maxPixelRatio': maxPixelRatio.toString(),
        if (debugPaint != null) 'debugPaint': debugPaint.toString(),
      },
    );
    return response.json!['result'] as String?;
  }

  // ---------------------------------------------------------------------------
  // Internal

  /// Unwraps the `result` key from an inspector extension response.
  ///
  /// Inspector extensions return `{'result': node}` rather than the node
  /// directly. This helper extracts the inner map.
  Map<String, dynamic> _result(Response response) {
    return response.json!['result'] as Map<String, dynamic>;
  }

  /// Calls [method] on the first isolate that has it registered.
  ///
  /// Throws an [RPCError] if no isolate has the extension registered.
  Future<Response> _callExtension(
    String method, {
    Map<String, dynamic>? args,
  }) async {
    final String isolateId = await _isolateIdForExtension(method);
    return _vmService.callServiceExtension(
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
    final VM vm = await _vmService.getVM();
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Isolate isolate = await _vmService.getIsolate(ref.id!);
      if (isolate.extensionRPCs?.contains(extension) == true) {
        return ref.id!;
      }
    }
    throw rpcError('No isolate found with extension: $extension');
  }
}

RPCError rpcError(String message, {String? fromMethod}) =>
    RPCError(fromMethod, 0, message);
