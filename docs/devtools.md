# DevTools Inspector Techniques

Notes collected from reading the Flutter DevTools source at
`packages/devtools_app/lib/src/shared/diagnostics/inspector_service.dart` and
related files. These cover patterns that are useful for implementing
`flutter-agent-tools` but are not documented in one place elsewhere.

**Source files referenced:**

- `packages/devtools_app/lib/src/shared/diagnostics/inspector_service.dart`
- `packages/devtools_app/lib/src/shared/diagnostics/diagnostics_node.dart`
- `packages/devtools_app/lib/src/shared/diagnostics/object_group_api.dart`
- `packages/devtools_app_shared/lib/src/service/constants.dart`
- `packages/devtools_app/lib/src/screens/logging/logging_controller.dart`
- `packages/devtools_app/lib/src/screens/inspector_v2/inspector_controller.dart`

---

## 1. Extension Name Constants

All Flutter inspector extensions are prefixed with `ext.flutter.inspector`.
DevTools defines this prefix as the constant `inspectorExtensionPrefix`:

```dart
const inspectorExtensionPrefix = 'ext.flutter.inspector';
// packages/devtools_app_shared/lib/src/service/service_extensions.dart:293
```

The inspector singleton inside the app is `WidgetInspectorService.instance`.
DevTools always uses the daemon API (JSON over `callServiceExtension`) rather
than the observatory `eval` path in production. The eval path exists as a
fallback but is rarely used.

---

## 2. Full List of `ext.flutter.inspector.*` Extensions

The canonical list of extension names comes from the Flutter framework's
`WidgetInspectorServiceExtensions` enum. DevTools calls all of the following:

| Extension name              | Key params                                                       | Returns              |
| --------------------------- | ---------------------------------------------------------------- | -------------------- |
| `getRootWidget`             | `objectGroup`                                                    | DiagnosticsNode JSON |
| `getRootWidgetTree`         | `groupName`, `isSummaryTree`, `withPreviews`, `fullDetails`      | DiagnosticsNode JSON |
| `getDetailsSubtree`         | `objectGroup`, `arg` (valueId), `subtreeDepth`                   | DiagnosticsNode JSON |
| `getChildren`               | `arg` (nodeRef.id), `objectGroup`                                | List of nodes        |
| `getChildrenSummaryTree`    | `arg` (nodeRef.id), `objectGroup`                                | List of nodes        |
| `getChildrenDetailsSubtree` | `arg` (nodeRef.id), `objectGroup`                                | List of nodes        |
| `getProperties`             | `arg` (nodeRef.id), `objectGroup`                                | List of nodes        |
| `getParentChain`            | `arg` (valueId), `objectGroup`                                   | DiagnosticsNode JSON |
| `getSelectedWidget`         | `objectGroup`                                                    | DiagnosticsNode JSON |
| `getSelectedSummaryWidget`  | `objectGroup`                                                    | DiagnosticsNode JSON |
| `setSelectionById`          | `arg` (widgetId), `objectGroup`                                  | bool                 |
| `getLayoutExplorerNode`     | `groupName`, `id` (valueId), `subtreeDepth`                      | DiagnosticsNode JSON |
| `setFlexProperties`         | `id`, `mainAxisAlignment`, `crossAxisAlignment`                  | void                 |
| `setFlexFactor`             | `id`, `flexFactor`                                               | void                 |
| `setFlexFit`                | `id`, `flexFit`                                                  | void                 |
| `getPubRootDirectories`     | (none)                                                           | List\<String\>       |
| `addPubRootDirectories`     | `arg0`, `arg1`, … (indexed)                                      | void                 |
| `removePubRootDirectories`  | `arg0`, `arg1`, … (indexed)                                      | void                 |
| `isWidgetTreeReady`         | (none)                                                           | bool                 |
| `isWidgetCreationTracked`   | (none)                                                           | bool                 |
| `disposeGroup`              | `objectGroup`                                                    | void                 |
| `screenshot`                | `id`, `width`, `height`, `margin`, `maxPixelRatio`, `debugPaint` | base64 PNG string    |
| `widgetLocationIdMap`       | (none)                                                           | Map\<id, location\>  |

### Parameter name inconsistency: `groupName` vs `objectGroup`

This is a real quirk in the Flutter inspector protocol — there is **no
consistent parameter name** for the object group:

- `getRootWidgetTree` and `getLayoutExplorerNode` use **`groupName`**.
- `getDetailsSubtree`, `getChildren*`, `getProperties`, `setSelectionById`,
  `getRootWidget`, `getParentChain`, and `screenshot` use **`objectGroup`** (or
  pass it as the second positional arg in the observatory eval path).
- `addPubRootDirectories` / `removePubRootDirectories` use indexed args: `arg0`,
  `arg1`, etc. (no group at all).

DevTools works around this by having two internal call helpers:
`invokeServiceMethodDaemonParams` (arbitrary key→value map) and
`invokeServiceMethodDaemonNoGroupArgs` (indexed arg list). The groupName/
objectGroup distinction must be respected exactly — the wrong key is silently
ignored and the object group won't be registered.

---

## 3. Object Groups — Memory Management

The inspector protocol uses **object groups** to manage the lifetime of
server-side Dart object references. Every inspector call that returns a
`DiagnosticsNode` is associated with a named group. The app holds strong
references to all objects in a group until `disposeGroup` is called, preventing
GC of the objects while you are using them.

**Pattern:**

1. Pick a group name (any non-empty string; DevTools uses `'selection'`,
   `'tree'`, `'details'`, etc.).
2. Pass it as `groupName` or `objectGroup` in every call.
3. When done with a batch of results, call `disposeGroup` with the same name.

**DevTools object group lifecycle** (from `InspectorObjectGroupManager`):

- Maintains two slots: `_current` and `_next`.
- Fetches a new tree into `_next` while `_current` is still being displayed.
- On `promoteNext()`: disposes `_current`, makes `_next` the new `_current`.
- On `cancelNext()`: disposes `_next` without promoting.

For a simple MCP server that makes one call at a time, a single static group
name (`'flutter_agent_tools'` or similar) is fine, but you should periodically
call `disposeGroup` to release references. If you never dispose, objects
accumulate in the app's memory.

---

## 4. `getRootWidgetTree` Parameters in Detail

```dart
// DevTools call (inspector_service.dart:979)
invokeServiceMethodDaemonParams(
  'getRootWidgetTree',
  {
    'groupName': groupName,
    'isSummaryTree': 'true',   // string "true"/"false", not a bool
    'withPreviews': 'true',    // include widget preview thumbnails
    'fullDetails': 'true',     // include render object data inline
  },
);
```

All boolean and numeric parameters are passed as **strings**, not native JSON
booleans/numbers.

`isSummaryTree: true` (the summary tree) omits lower-level framework-internal
widgets (e.g. `_InheritedProviderScope`, raw `Listener` wrappers). It is the
right default for most agent use cases. Use `false` only when you need the
complete unfiltered widget tree.

`fullDetails: true` includes the render object and its layout properties
(constraints, size, parentData) inline in each node. Without this, you need a
separate `getDetailsSubtree` call to get render data.

`withPreviews: true` includes small PNG thumbnails of each visible widget
embedded in the JSON. Useful in the DevTools UI; expensive and noisy for agents
— set to `false` unless you specifically need thumbnails.

---

## 5. The `getDetailsSubtree` / `getLayoutExplorerNode` Pattern

When you need the render-object layout data for a specific widget:

```dart
// Get full layout data for the widget identified by its valueId:
invokeServiceMethodDaemonParams(
  'getDetailsSubtree',
  {
    'objectGroup': groupName,    // note: "objectGroup", not "groupName"
    'arg': node.valueId,         // the valueId from a previous tree call
    'subtreeDepth': '2',         // string; default 2 in DevTools
  },
);
```

The response includes the widget's properties AND a `renderObject` node
containing `constraints`, `size`, `parentData` as structured sub-maps (not
strings — they are already parsed by the framework before transmission).

`getLayoutExplorerNode` is a variant that returns flex-specific layout data
(flex factor, fit, alignment) suitable for the Layout Explorer UI:

```dart
invokeServiceMethodDaemonParams(
  'getLayoutExplorerNode',
  {
    'groupName': groupName,      // note: "groupName" here
    'id': node.valueId,
    'subtreeDepth': '1',
  },
);
```

---

## 6. DiagnosticsNode JSON Shape

### Tree call responses (`getRootWidgetTree`, `getDetailsSubtree`, etc.)

Inspector extensions return `{ 'result': <node>, 'errorMessage': null }`. Always
extract via `response.json['result']`.

A `DiagnosticsNode` JSON object has these key fields:

```jsonc
{
  "description": "MyWidget",            // human-readable label
  "name": "child",                      // property name (if this is a property)
  "type": "DiagnosticableTreeNode",     // Dart runtime type of the node
  "widgetRuntimeType": "MyWidget",      // widget class name (summary tree only)
  "level": "info",                      // diagnostic level (omitted when "info")
  "style": "sparse",                    // display style (omitted when "sparse")
  "valueId": "inspector-42",            // object handle (present in full detail)
  "hasChildren": true,                  // true if children exist but not fetched
  "truncated": false,                   // true if child list was cut off
  "summaryTree": false,                 // true if this came from a summary tree call
  "shouldIndent": true,                 // display hint
  "children": [ ... ],                  // nested DiagnosticsNode objects
  "properties": [ ... ],                // property DiagnosticsNode objects
  "creationLocation": {                 // only present when widget creation tracking is on
    "file": "file:///path/to/lib/main.dart",
    "line": 42,
    "column": 8,
    "name": "MyWidget"
  }
}
```

### Render object sub-map (in `getDetailsSubtree` responses)

When `fullDetails: true` or via `getDetailsSubtree`, the `renderObject` property
is an inlined DiagnosticsNode whose `properties` include:

```jsonc
{
  "name": "renderObject",
  "properties": [
    {
      "name": "constraints",
      "description": "BoxConstraints(w=390.0, h=844.0)",
    },
    { "name": "size", "description": "Size(390.0, 200.0)" },
    { "name": "parentData", "description": "offset=Offset(0.0, 0.0)" },
  ],
}
```

**Note:** DevTools also exposes `constraints` and `size` as structured sub-maps
under `json['constraints']` and `json['size']` (with `minWidth`/`maxWidth`/etc.
and `width`/`height` keys respectively), but these are present only in the
details subtree response, not the summary tree.

DevTools deserializes them as:

```dart
static BoxConstraints deserializeConstraints(Map<String, Object?> json) {
  return BoxConstraints(
    minWidth:  double.parse(json['minWidth']  as String? ?? '0.0'),
    maxWidth:  double.parse(json['maxWidth']  as String? ?? 'Infinity'),
    minHeight: double.parse(json['minHeight'] as String? ?? '0.0'),
    maxHeight: double.parse(json['maxHeight'] as String? ?? 'Infinity'),
  );
}

static Size? deserializeSize(Map<String, Object> json) {
  final width  = json['width']  as String?;
  final height = json['height'] as String?;
  if (width == null || height == null) return null;
  return Size(double.parse(width), double.parse(height));
}
```

---

## 7. Going from a `valueId` to a VM Service Object ID

Inspector `valueId` strings (e.g. `"inspector-42"`) are scoped to the Flutter
inspector protocol. They **cannot** be passed directly to the VM service
`evaluate` RPC as a target object. To evaluate an expression on a specific
widget, you must first convert the `valueId` to a raw VM object ID.

**DevTools's approach** (`evalOnRef`, `inspector_service.dart:879`):

```dart
// Evaluates `expression` with `object` bound to the widget identified
// by its inspector ref:
inspectorLibrary.eval(
  "((object) => $expression)"
  "(WidgetInspectorService.instance.toObject('${inspectorRef.id}'))",
  isAlive: this,
);
```

This calls `WidgetInspectorService.instance.toObject(id)` inside the app to
resolve the inspector handle back to the live Dart object, then immediately
invokes the lambda. `inspectorLibrary` is an `EvalOnDartLibrary` scoped to
`package:flutter/src/widgets/widget_inspector.dart`.

**Alternative path** — `toObservatoryInstanceRef`:

```dart
// inspector_service.dart:740
// Calls "toObject" via the daemon API and returns a raw InstanceRef:
invokeServiceMethodObservatoryInspectorRef('toObject', inspectorInstanceRef)
// → eval: "WidgetInspectorService.instance.toObject('inspector-42', 'groupName')"
// → returns InstanceRef with .id = "objects/1234"
```

Once you have a raw VM object ID (`"objects/1234"`), you can use it as the
`targetId` in the VM service `evaluate` RPC:

```dart
vmService.evaluate(isolateId, 'objects/1234', 'runtimeType.toString()');
```

**Practical recipe for flutter-agent-tools:**

1. Call `getRootWidgetTree` or `getDetailsSubtree` to get a node with a
   `valueId`.
2. Evaluate `WidgetInspectorService.instance.toObject(valueId)` in the inspector
   library scope (`package:flutter/src/widgets/widget_inspector.dart`). The
   result `InstanceRef.id` is the raw VM object ID.
3. Call `vmService.evaluate` with that VM object ID as the target to run
   arbitrary expressions on that widget's instance members.

---

## 8. Pub Root Directories — Distinguishing Local from Framework Widgets

DevTools uses `addPubRootDirectories` / `getPubRootDirectories` to tell the
inspector which source directories belong to the current project. This is used
to colour-code the widget tree (local vs framework) and to filter the summary
tree.

```dart
// Register the project's source root(s):
invokeServiceMethodDaemonNoGroupArgs(
  'addPubRootDirectories',
  ['/path/to/my_app/lib'],  // passed as arg0, arg1, etc.
);
```

When a `DiagnosticsNode` has `creationLocation.file` set, DevTools checks
whether that path is under one of the registered pub roots. Nodes from outside
the roots are considered framework/package widgets.

**For flutter-agent-tools**, the simpler approach (already implemented in
`route_formatter.dart`) is to check whether the file path contains
`/.pub-cache/` directly. This is more robust than relying on
`addPubRootDirectories` because it doesn't require registration and works
correctly for local packages vendored via `path:` dependencies.

Note: `creationLocation` is only populated when widget creation tracking is
enabled (debug mode with `isWidgetCreationTracked()` returning `true`).

---

## 9. The `Flutter.Navigation` Event

The VM service emits a `Flutter.Navigation` extension event whenever the
Navigator stack changes. The event carries the current route's description:

```dart
// Event shape (logging_controller.dart:1115):
// event.extensionData.data == {
//   'route': {
//     'description': '/home',     // route name / description string
//     ...
//   }
// }
String? routeDescription = event.extensionData!.data['route']?['description'];
```

**Important**: DevTools does NOT refresh the inspector immediately on
`Flutter.Navigation`. It waits for the next `Flutter.Frame` event after the
navigation event, because Flutter may not have repainted the UI yet:

```dart
// inspector_controller.dart:465
if (extensionEventKind == 'Flutter.Navigation') {
  _receivedFlutterNavigationEvent = true;
}
if (_receivedFlutterNavigationEvent && extensionEventKind == 'Flutter.Frame') {
  _receivedFlutterNavigationEvent = false;
  await refreshInspector();  // now the tree is up to date
}
```

For `flutter_query_ui(mode: 'route')`, if the caller navigated recently it
should either wait for a `Flutter.Frame` event or add a small delay before
fetching the widget tree.

**The `Flutter.Navigation` event does not include the route path string** (e.g.
`/podcast/123`). It only carries the route's `description`, which for go_router
routes is typically the widget class name, not the path. To get a route path you
would need to evaluate `GoRouter.of(context).location` — but that requires a
valid `BuildContext`, which is not cheaply available from the VM service.

---

## 10. Flutter VM Service Extension Events (Full List)

These are sent as `kind: kExtension` VM service events and consumed via
`service.onExtensionEvent`:

| Event kind                             | Description                                    |
| -------------------------------------- | ---------------------------------------------- |
| `Flutter.Error`                        | Unhandled Flutter framework error (structured) |
| `Flutter.Frame`                        | Each rendered frame (with timing data)         |
| `Flutter.FirstFrame`                   | First frame after app start / hot restart      |
| `Flutter.FrameworkInitialization`      | Framework init complete                        |
| `Flutter.Navigation`                   | Navigator stack change                         |
| `Flutter.Print`                        | `debugPrint()` output                          |
| `Flutter.RebuiltWidgets`               | Widgets rebuilt in last frame (performance)    |
| `Flutter.ImageSizesForFrame`           | Image decoding sizes for current frame         |
| `Flutter.ServiceExtensionStateChanged` | A service extension was toggled                |

---

## 11. `isWidgetTreeReady` / `isWidgetCreationTracked`

Before making tree calls, check both:

```dart
// Returns false if the widget tree hasn't been built yet (e.g. app just
// launched). If false, wait for the next Flutter.Frame event.
bool ready = await invokeServiceMethod('isWidgetTreeReady');

// Returns true only in debug builds with `--track-widget-creation` (the
// default for `flutter run`). If false, creationLocation is absent from
// all DiagnosticsNode responses.
bool tracked = await invokeServiceMethod('isWidgetCreationTracked');
```

---

## 12. `widgetLocationIdMap`

An extension that returns a full map of widget creation IDs to source locations,
without needing to traverse the tree. Useful for static analysis of the app's
widget structure:

```dart
// Returns: { 'widgetId': { 'file': '...', 'line': 42, 'column': 8 }, ... }
Map<String, Object?> locationMap = await invokeServiceMethod('widgetLocationIdMap');
```

---

## 13. `getParentChain`

Returns the ancestor chain from the root down to the widget identified by
`valueId`. Each node in the chain has its children populated just enough to show
the path. This is more efficient than fetching the full tree when you already
have a widget's `valueId` and want to understand its context:

```dart
invokeServiceMethodDaemonParams(
  'getParentChain',
  {'arg': valueId, 'objectGroup': groupName},
);
```

---

## 14. Evaluating Expressions — Scope Details

The VM service `evaluate` RPC can target three different scopes:

| Target     | Scope                                              | When to use                          |
| ---------- | -------------------------------------------------- | ------------------------------------ |
| Library ID | Root library of the isolate (`isolate.rootLib.id`) | Top-level globals, bindings, etc.    |
| Class ID   | Static members of a class                          | Rarely needed from an MCP server     |
| Object ID  | Instance members; `this` = the target object       | Evaluate on a specific widget/object |

The root library scope gives access to everything imported in `main.dart`, which
includes `WidgetsBinding.instance`, `GoRouter`, top-level variables, etc.

**Getting the root library ID:**

```dart
final Isolate isolate = await vmService.getIsolate(isolateRef.id!);
final String libId = isolate.rootLib!.id!;
await vmService.evaluate(isolateRef.id!, libId, expression);
```

**Converting an inspector `valueId` to an object ID for `evaluate`:**

```dart
// Evaluate this in the inspector library scope
// (library URI: package:flutter/src/widgets/widget_inspector.dart):
final result = await vmService.evaluate(
  isolateId,
  inspectorLibraryId,
  "WidgetInspectorService.instance.toObject('$valueId')",
) as InstanceRef;
final String vmObjectId = result.id!;  // e.g. "objects/1234"

// Now evaluate on the widget instance:
await vmService.evaluate(isolateId, vmObjectId, 'runtimeType.toString()');
```

---

## 15. Screenshot Extension Details

`ext.flutter.inspector.screenshot` renders a specific widget to a PNG and
returns it as a base64-encoded string:

```dart
callServiceExtension(
  'ext.flutter.inspector.screenshot',
  args: {
    'id': valueId,                  // inspector object handle (not VM object ID)
    'width': width.toString(),      // logical pixels, string
    'height': height.toString(),    // logical pixels, string
    'margin': '0.0',                // optional; extra margin around widget
    'maxPixelRatio': '1.0',         // optional; device pixel ratio multiplier
    'debugPaint': 'false',          // optional; overlay debug paint lines
  },
);
// response.json['result'] is a base64 PNG string, or null if not visible
```

The `id` here is the inspector `valueId` (e.g. `"inspector-42"`), **not** a VM
object ID. This is one of the few extensions that takes `id` rather than `arg`
as the key.

To screenshot the full app window, use the root widget's `valueId` from
`getRootWidget()`.

---

## 16. The `structuredErrors` Extension Toggle

Flutter's structured error reporting (the `Flutter.Error` extension events) is
controlled by the `ext.flutter.inspector.structuredErrors` toggle:

```dart
callServiceExtension(
  'ext.flutter.inspector.structuredErrors',
  args: {'enabled': 'true'},
);
```

When enabled, errors are delivered as structured `DiagnosticsNode` JSON via
`Flutter.Error` extension events rather than plain text stderr. This must be
enabled before errors occur to receive them in structured form; enabling it
after the fact does not replay prior errors.

---

## 17. Reading the `Flutter.Error` Event

When structured errors are enabled, each unhandled Flutter error arrives as a VM
service extension event with `extensionKind == 'Flutter.Error'`. The
`extensionData.data` field is a `DiagnosticsNode` JSON tree. Key node types:

| `type` field             | Content                                                       |
| ------------------------ | ------------------------------------------------------------- |
| `ErrorSummary`           | The one-line error message (`level == 'summary'`)             |
| `ErrorDescription`       | Prose context paragraph                                       |
| `ErrorHint`              | Suggested fix                                                 |
| `DiagnosticsBlock`       | Named group of sub-nodes (e.g. "The relevant error widget")   |
| `DiagnosticableTreeNode` | The offending widget; sub-properties: constraints, size, etc. |
| `DiagnosticsStackTrace`  | Stack frames; first frame is the call site                    |

A `DiagnosticableTreeNode` inside the error data may include a `valueId`; this
can be passed to `getDetailsSubtree` or `inspect_layout` for a layout
drill-down.

---

## 18. Summary of Confirmed Quirks

- **Boolean params are strings.** Pass `'true'`/`'false'`, not `true`/`false`.
- **Group key inconsistency.** Some extensions take `groupName`, others take
  `objectGroup`. Getting this wrong silently omits group registration.
- **`getParentChain` vs `getDetailsSubtree`.** For navigating up the tree use
  `getParentChain`; for navigating into layout details use `getDetailsSubtree`.
- **`valueId` ≠ VM object ID.** Inspector IDs are protocol-scoped. Use
  `WidgetInspectorService.instance.toObject(id)` to bridge them.
- **Summary tree `widgetRuntimeType` vs full tree `type`.** In summary tree
  responses the widget class name is in `widgetRuntimeType`; in full detail
  responses it is in `type` (the Dart runtime type of the DiagnosticsNode
  wrapper, not the widget itself). Both may be present.
- **`Flutter.Navigation` → wait for `Flutter.Frame`.** The tree is not repainted
  at the moment of navigation; always wait for the next frame event before
  fetching the widget tree after a navigation.
- **`screenshot` uses `id`, not `arg`.** Other single-object extensions use
  `arg` for the `valueId`; screenshot is the exception.
