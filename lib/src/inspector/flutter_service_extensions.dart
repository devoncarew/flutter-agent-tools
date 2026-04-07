import 'package:vm_service/vm_service.dart';

import 'diagnostics_node.dart';
import 'app_session.dart';
import 'utils.dart';

/// Provides 1:1 access to Flutter VM service extensions.
///
/// Each method maps directly to one `ext.flutter.*` service extension call.
/// Higher-level convenience methods that combine multiple calls belong in
/// [AppSession] instead.
class FlutterServiceExtensions {
  // Object group name used for inspector extension calls. The inspector uses
  // groups to manage the lifetime of server-side object references.
  static const String inspectorGroup = 'flutter_agent_tools';

  final VmService _vmService;

  /// A debug-time only logger; this can send log statements back to the host
  /// MCP client.
  final Logger? debugLogger;

  FlutterServiceExtensions(this._vmService, {this.debugLogger});

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
  // Semantics

  /// Enables the Flutter semantics tree.
  ///
  /// Evaluates `RendererBinding.instance.ensureSemantics()` on the main
  /// isolate. The returned [SemanticsHandle] is intentionally not retained —
  /// Dart's GC does not call [SemanticsHandle.dispose], so the reference
  /// count stays incremented and the semantics tree remains active for the
  /// lifetime of the app process.
  ///
  /// Safe to call multiple times.
  Future<void> enableSemantics() async {
    // RendererBinding is not in the app's root library scope, so we evaluate
    // in widget_inspector.dart which imports package:flutter/rendering.dart.
    await evaluate(
      'RendererBinding.instance.ensureSemantics()',
      libraryUri: 'package:flutter/src/widgets/widget_inspector.dart',
    );
  }

  /// Returns a JSON string representing the current semantics tree.
  ///
  /// Each node in the JSON tree has the shape:
  /// ```json
  /// {
  ///   "id": 42,
  ///   "role": "button",
  ///   "label": "Sign in",
  ///   "value": "",
  ///   "hint": "Double tap to activate",
  ///   "tooltip": "",
  ///   "checked": null,
  ///   "toggled": null,
  ///   "selected": null,
  ///   "enabled": true,
  ///   "focused": false,
  ///   "actions": 1,
  ///   "rect": [100.0, 200.0, 200.0, 250.0],
  ///   "children": []
  /// }
  /// ```
  ///
  /// `role` is one of: `"button"`, `"textfield"`, `"slider"`, `"link"`,
  /// `"image"`, `"header"`, `"checkbox"`, `"toggle"`, `"radio"`, or `""`
  /// (generic/container). State fields (`checked`, `toggled`, `selected`,
  /// `enabled`) are `null` when the concept does not apply to the node.
  /// `rect` is `[left, top, right, bottom]` in the node's local coordinate
  /// space (the root's local space is screen coordinates).
  /// `actions` is a [SemanticsAction] bitmask.
  ///
  /// Returns `{"error":"..."}` if semantics is not yet enabled or the tree
  /// is empty. Throws an [RPCError] on VM service failures.
  ///
  /// The expression is evaluated in the `semantics.dart` library scope, where
  /// `SemanticsNode`, `SemanticsBinding`, `CheckedState`, and `Tristate` are
  /// all in scope. `RendererBinding` is accessed via
  /// `(SemanticsBinding.instance as dynamic).pipelineOwner`.
  Future<String> getSemanticsTree() async {
    // Evaluate in semantics.dart scope: SemanticsNode, SemanticsBinding,
    // CheckedState, and Tristate are all in scope there. RendererBinding is
    // not in scope, but we access pipelineOwner via
    // (SemanticsBinding.instance as dynamic).pipelineOwner.
    const String inspectorLibUri =
        'package:flutter/src/semantics/semantics.dart';

    final VM vm = await _vmService.getVM();
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Isolate isolate = await _vmService.getIsolate(ref.id!);
      final String? libId = _libraryIdForUri(isolate, inspectorLibUri);
      if (libId == null) continue;

      final Response result = await _vmService.evaluate(
        ref.id!,
        libId,
        _kSemanticsTreeExpression,
      );

      if (result is ErrorRef) {
        throw rpcError(
          result.message ?? 'getSemanticsTree failed',
          fromMethod: 'getSemanticsTree',
        );
      }
      if (result is InstanceRef) {
        // valueAsString is truncated for long strings — fetch the full object.
        if (result.valueAsStringIsTruncated == true) {
          final obj = await _vmService.getObject(ref.id!, result.id!);
          if (obj is Instance) {
            return obj.valueAsString ?? '{"error":"null result"}';
          }
        }
        return result.valueAsString ?? '{"error":"null result"}';
      }
    }
    throw rpcError(
      'No suitable isolate found for getSemanticsTree',
      fromMethod: 'getSemanticsTree',
    );
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
    return DiagnosticsNode.fromJson(_unwrapResponse('getRootWidget', response));
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
    return DiagnosticsNode.fromJson(
      _unwrapResponse('getRootWidgetTree', response),
    );
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

    return DiagnosticsNode.fromJson(
      _unwrapResponse('getDetailsSubtree', response),
    );
  }

  // ---------------------------------------------------------------------------
  // ext.flutter.inspector.getParentChain

  /// Returns the chain of ancestor nodes from the root down to the widget with
  /// [diagnosticableId], as a [DiagnosticsNode].
  ///
  /// Useful for understanding where a widget sits in the overall tree without
  /// needing to walk the entire tree from the root. Each node in the chain has
  /// its children populated only enough to show the path.
  Future<DiagnosticsNode> getParentChain(String diagnosticableId) async {
    final Response response = await _callExtension(
      'ext.flutter.inspector.getParentChain',
      args: {'arg': diagnosticableId, 'objectGroup': inspectorGroup},
    );
    return DiagnosticsNode.fromJson(
      _unwrapResponse('getParentChain', response),
    );
  }

  // ---------------------------------------------------------------------------
  // VM service evaluate on an object instance

  /// Evaluates [expression] in the context of the VM object with [vmObjectId].
  ///
  /// Unlike [evaluate] (which runs in the root library scope), this evaluates
  /// with `this` bound to the specified object — fields and methods of that
  /// object are directly in scope.
  ///
  /// [vmObjectId] must be a raw VM service object ID (e.g. `objects/123`), as
  /// returned by [evaluateToObjectId]. Inspector group handles such as
  /// `inspector-29` are NOT valid here — those are scoped to the Flutter
  /// inspector protocol and cannot be used directly as VM evaluate targets.
  ///
  /// Returns the `toString()` of the result. Throws an [RPCError] on failure.
  Future<String> evaluateOnObject(String vmObjectId, String expression) async {
    final VM vm = await _vmService.getVM();
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Response result = await _vmService.evaluate(
        ref.id!,
        vmObjectId,
        expression,
      );

      if (result is ErrorRef) {
        throw rpcError(
          result.message ?? 'evaluateOnObject failed',
          fromMethod: 'evaluateOnObject',
        );
      }
      if (result is InstanceRef) {
        return result.valueAsString ??
            result.classRef?.name ??
            result.kind ??
            '?';
      }
    }
    throw rpcError(
      'No suitable isolate found for evaluateOnObject',
      fromMethod: 'evaluateOnObject',
    );
  }

  /// Evaluates [expression] in the root library scope and returns the raw VM
  /// service object ID of the result, rather than its string representation.
  ///
  /// Use this to obtain a [vmObjectId] for [evaluateOnObject]. For example,
  /// to call methods on a GoRouter stored as a top-level variable `_router`:
  ///
  /// ```dart
  /// final id = await extensions.evaluateToObjectId('_router');
  /// final result = await extensions.evaluateOnObject(id, 'go("/home")');
  /// ```
  ///
  /// Returns null if the result has no object identity (e.g. it is a primitive
  /// like `int` or `String`). Throws an [RPCError] on failure.
  Future<String?> evaluateToObjectId(String expression) async {
    final VM vm = await _vmService.getVM();
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Isolate isolate = await _vmService.getIsolate(ref.id!);
      final String? libId = isolate.rootLib?.id;
      if (libId == null) continue;

      final Response result = await _vmService.evaluate(
        ref.id!,
        libId,
        expression,
      );

      if (result is ErrorRef) {
        throw rpcError(
          result.message ?? 'evaluateToObjectId failed',
          fromMethod: 'evaluateToObjectId',
        );
      }
      if (result is InstanceRef) {
        return result.id;
      }
    }
    throw rpcError(
      'No suitable isolate found for evaluateToObjectId',
      fromMethod: 'evaluateToObjectId',
    );
  }

  /// Converts an inspector `valueId` (e.g. `"inspector-42"`) to a raw VM
  /// service object ID (e.g. `"objects/1234"`) suitable for use with
  /// [evaluateOnObject].
  ///
  /// Inspector handles are scoped to the Flutter inspector protocol and cannot
  /// be passed directly to the VM service `evaluate` RPC as a target object.
  /// This method bridges them by evaluating
  /// `WidgetInspectorService.instance.toObject(valueId)` in the inspector
  /// library scope — the same technique used by DevTools (`evalOnRef` in
  /// `inspector_service.dart`).
  ///
  /// Returns null if the inspector handle cannot be resolved (e.g. the object
  /// has been garbage collected or the group was disposed). Throws an [RPCError]
  /// on failure.
  Future<String?> inspectorIdToVmObjectId(String valueId) async {
    const String inspectorLibUri =
        'package:flutter/src/widgets/widget_inspector.dart';

    final VM vm = await _vmService.getVM();
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Isolate isolate = await _vmService.getIsolate(ref.id!);
      final String? libId = _libraryIdForUri(isolate, inspectorLibUri);
      if (libId == null) continue;

      final Response result = await _vmService.evaluate(
        ref.id!,
        libId,
        "WidgetInspectorService.instance.toObject('$valueId')",
      );

      if (result is ErrorRef) {
        throw rpcError(
          result.message ?? 'inspectorIdToVmObjectId failed',
          fromMethod: 'inspectorIdToVmObjectId',
        );
      }
      if (result is InstanceRef) {
        return result.id;
      }
    }
    throw rpcError(
      'No suitable isolate found for inspectorIdToVmObjectId',
      fromMethod: 'inspectorIdToVmObjectId',
    );
  }

  /// Returns the library ID for the library with [uri] in [isolate], or null
  /// if no such library is loaded.
  String? _libraryIdForUri(Isolate isolate, String uri) {
    for (final lib in isolate.libraries ?? <LibraryRef>[]) {
      if (lib.uri == uri) return lib.id;
    }
    return null;
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
  // VM service evaluate

  /// Evaluates [expression] on the main isolate and returns the result as a
  /// string.
  ///
  /// By default the expression is evaluated in the context of the isolate's
  /// root library (`main.dart`), so top-level declarations and globals like
  /// `WidgetsBinding.instance` are in scope.
  ///
  /// Pass [libraryUri] to evaluate in a different library scope. For example,
  /// `package:flutter/src/widgets/widget_inspector.dart` imports
  /// `package:flutter/rendering.dart` and `dart:ui`, making `RendererBinding`,
  /// `SemanticsNode`, `CheckedState`, `Tristate`, etc. available.
  ///
  /// Returns the `toString()` of the result. Throws an [RPCError] if the
  /// expression fails to compile or throws at runtime — the error message
  /// includes the Dart exception text.
  Future<String> evaluate(String expression, {String? libraryUri}) async {
    final VM vm = await _vmService.getVM();
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Isolate isolate = await _vmService.getIsolate(ref.id!);
      final String? libId =
          libraryUri != null
              ? _libraryIdForUri(isolate, libraryUri)
              : isolate.rootLib?.id;
      if (libId == null) continue;

      final Response result = await _vmService.evaluate(
        ref.id!,
        libId,
        expression,
      );

      if (result is ErrorRef) {
        throw rpcError(
          result.message ?? 'evaluate failed',
          fromMethod: 'evaluate',
        );
      }
      if (result is InstanceRef) {
        // Primitive values (String, int, double, bool, null) have their value
        // inline. For other types, valueAsString holds the toString() output.
        return result.valueAsString ??
            result.classRef?.name ??
            result.kind ??
            '?';
      }
    }
    throw rpcError(
      'No suitable isolate found for evaluate',
      fromMethod: 'evaluate',
    );
  }

  // ---------------------------------------------------------------------------
  // Window size via VM service evaluate

  /// Returns the physical window size by evaluating a Dart expression on the
  /// main isolate.
  ///
  /// This avoids the inspector extension string-parsing path entirely — the VM
  /// service `evaluate` RPC runs real Dart code and returns the exact value.
  /// Returns null if the expression cannot be evaluated or the result cannot
  /// be parsed.
  Future<(double, double)?> getPhysicalWindowSize() async {
    final VM vm = await _vmService.getVM();
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Isolate isolate = await _vmService.getIsolate(ref.id!);
      final String? libId = isolate.rootLib?.id;
      if (libId == null) continue;

      final Response result = await _vmService.evaluate(
        ref.id!,
        libId,
        'WidgetsBinding.instance.platformDispatcher.views.first.physicalSize'
        '.toString()',
      );

      if (result is InstanceRef && result.valueAsString != null) {
        final match = _sizeRegExp.firstMatch(result.valueAsString!);
        if (match != null) {
          return (double.parse(match.group(1)!), double.parse(match.group(2)!));
        }
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Size helpers

  /// Returns the logical size of the widget with [diagnosticableId] by
  /// examining its details subtree. Returns null values if the size cannot be
  /// determined.
  Future<(double?, double?)> getWidgetSize(String diagnosticableId) async {
    try {
      // Depth 4 to ensure we reach the RenderBox node, which may be several
      // levels below the root element in the details subtree.
      final DiagnosticsNode node = await getDetailsSubtree(
        diagnosticableId,
        subtreeDepth: 4,
      );
      final (double, double)? size = _extractSize(node);
      if (size != null) return size;
    } catch (_) {
      // Fall through to null.
    }
    return (null, null);
  }

  /// Extracts a logical pixel size from [node]'s details subtree.
  ///
  /// Navigates to the `renderObject` property and reads its `view size`
  /// property, which contains the logical pixel dimensions as a string like
  /// "Size(390.0, 844.0)". Recurses into children.
  (double, double)? _extractSize(DiagnosticsNode node) {
    final renderObject = node.propertyNamed('renderObject');
    final size = renderObject?.propertyNamed('view size');

    if (size != null) {
      final RegExpMatch? match = _sizeRegExp.firstMatch(size.description);
      if (match != null) {
        return (double.parse(match.group(1)!), double.parse(match.group(2)!));
      }
    }

    for (final DiagnosticsNode child in node.children) {
      final (double, double)? result = _extractSize(child);
      if (result != null) return result;
    }

    return null;
  }

  // "Size(740.0, 1645.6) (in physical pixels)"
  static final RegExp _sizeRegExp = RegExp(
    r'Size\((\d+\.?\d*),\s*(\d+\.?\d*)\)',
  );

  // ---------------------------------------------------------------------------
  // Internal

  /// Unwraps the `result` key from an inspector extension response.
  ///
  /// Inspector extensions return `{'result': node}` rather than the node
  /// directly. This helper extracts the inner map. Throws an [RPCError] if
  /// `result` is null or not a map — which happens when the widget ID is
  /// invalid or the object has been garbage collected.
  Map<String, dynamic> _unwrapResponse(
    String callingMethod,
    Response response,
  ) {
    if (response.json?['error'] != null) {
      throw RPCError.parse(callingMethod, response.json!['error']);
    }

    if (response.json!['result'] == null) {
      throw RPCError(
        callingMethod,
        0,
        'Widget ID invalid or object garbage collected',
      );
    }

    return (response.json!['result'] as Map).cast();
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

// ---------------------------------------------------------------------------
// Dart IIFE evaluated inside the running app to dump the semantics tree.
//
// Design constraints:
//   - No local named function declarations — some Dart VM evaluate
//     implementations do not support them. All logic is inlined.
//   - No '{' or '}' inside string literals — avoid potential brace-counting
//     bugs in simpler expression parsers. Error results use the prefix
//     "error:" and the data format uses JSON arrays ([]) not objects ({}).
//   - Evaluated in widget_inspector.dart library scope, which imports
//     package:flutter/rendering.dart and dart:ui so RendererBinding,
//     SemanticsNode, CheckedState, and Tristate are all in scope.
//
// Output: a flat JSON array of tuples, one per visible non-hidden node:
//   [[id, role, label, value, hint, checked, toggled, selected, enabled,
//     focused, actions, rectLeft, rectTop, rectRight, rectBottom], ...]
//
// Field indices (0-based):
//   0  id       int     — SemanticsNode.id (usable with performSemanticsAction)
//   1  role     String  — "button"|"textfield"|"slider"|"link"|"image"|
//                         "header"|"checkbox"|"toggle"|"radio"|""
//   2  label    String  — primary accessibility label
//   3  value    String  — current value (slider pos, text content, etc.)
//   4  hint     String  — hint text
//   5  checked  bool?   — null if not applicable
//   6  toggled  bool?   — null if not applicable (Switch)
//   7  selected bool?   — null if not applicable (Tab, ListItem)
//   8  enabled  bool?   — null if not applicable
//   9  focused  bool
//   10 actions  int     — SemanticsAction bitmask
//   11..14 rect doubles — left, top, right, bottom in local coordinates
//
// On error, returns the string "error:<message>".
// The expression must be a single line — the Dart VM evaluate endpoint does
// not support multi-line IIFE bodies. Named local functions and multi-line
// strings with { } characters also cause "Can't find '}' to match '{'" errors.
//
// Library scope: package:flutter/src/semantics/semantics.dart
// (SemanticsNode, SemanticsBinding, CheckedState, Tristate all in scope)
// RendererBinding is not in scope there, so we reach pipelineOwner via
// (SemanticsBinding.instance as dynamic).pipelineOwner.
const String _kSemanticsTreeExpression =
    r"""(() { final owner = (SemanticsBinding.instance as dynamic).pipelineOwner.semanticsOwner; if (owner == null) return 'error:semantics not enabled'; final root = owner.rootSemanticsNode; if (root == null) return 'error:semantics tree empty - retry after a frame renders'; final parts = []; final stack = [root]; while (stack.isNotEmpty) { final node = stack.removeLast(); if (node.isInvisible) continue; final d = node.getSemanticsData(); final f = d.flagsCollection; if (f.isHidden) continue; final r = node.rect; final role = f.isButton ? 'button' : f.isTextField ? 'textfield' : f.isSlider ? 'slider' : f.isLink ? 'link' : f.isImage ? 'image' : f.isHeader ? 'header' : f.isChecked != CheckedState.none ? 'checkbox' : f.isToggled != Tristate.none ? 'toggle' : f.isInMutuallyExclusiveGroup ? 'radio' : ''; final lb = '${node.label}'.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', ' '); final vl = '${node.value}'.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', ' '); final hn = '${node.hint}'.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', ' '); final checked = f.isChecked == CheckedState.none ? 'null' : f.isChecked == CheckedState.isTrue ? 'true' : 'false'; final toggled = f.isToggled == Tristate.none ? 'null' : f.isToggled == Tristate.isTrue ? 'true' : 'false'; final selected = f.isSelected == Tristate.none ? 'null' : f.isSelected == Tristate.isTrue ? 'true' : 'false'; final enabled = f.isEnabled == Tristate.none ? 'null' : f.isEnabled == Tristate.isTrue ? 'true' : 'false'; final focused = f.isFocused == Tristate.isTrue; parts.add('[${node.id},"$role","$lb","$vl","$hn",$checked,$toggled,$selected,$enabled,$focused,${d.actions},${r.left},${r.top},${r.right},${r.bottom}]'); if (!node.mergeAllDescendantsIntoThisNode) node.visitChildren((child) => (stack..add(child)).isNotEmpty); } return '[${parts.join(",")}]'; })()""";

RPCError rpcError(String message, {String? fromMethod}) =>
    RPCError(fromMethod, 0, message);
