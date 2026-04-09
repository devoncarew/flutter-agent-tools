# Slipstream

MCP servers, instructions, and tools,

## `packages` server

Tools for querying Dart and Flutter package APIs directly from the pub cache.

Use these tools when you need accurate, up-to-date API signatures for a package
rather than relying on training-data summaries, which are often subtly wrong.

Typical call sequence:

1. package_summary — orient on the package: version, library list, exported
   names.
2. library_stub — get full API signatures for one library.
3. class_stub — drill into a specific class when you know exactly what you need.

Source is the local pub cache — already downloaded, always matches the resolved
version in pubspec.lock, no network required.

### `packages:package_summary`

```
package_summary(project_directory, package)
```

Returns API summaries for Dart or Flutter packages; start here to orient on an
unfamiliar package. Use this to get accurate, version-matched API signatures
instead of relying on training-data summaries, which are often subtly wrong.

The returned package summary contains version, entry-point import, README
excerpt, public library list, and exported name groups for the main library.

- `project_directory`: (required) Absolute path to the Dart/Flutter project
  directory (the folder containing pubspec.yaml). Used to resolve the package
  version from pubspec.lock and to locate the package_config.json for analysis.
- `package`: (required) The package name (e.g. "http", "provider").

### `packages:library_stub`

```
library_stub(project_directory, package, library_uri)
```

Returns the full public API for one library as a Dart stub (signatures only, no
bodies).

- `project_directory`: (required) Absolute path to the Dart/Flutter project
  directory (the folder containing pubspec.yaml). Used to resolve the package
  version from pubspec.lock and to locate the package_config.json for analysis.
- `package`: (required) The package name (e.g. "http", "provider").
- `library_uri`: (required) The library URI to target, e.g.
  "package:http/http.dart".

### `packages:class_stub`

```
class_stub(project_directory, package, library_uri, class)
```

Returns the public API for a single named class, mixin, or extension as a Dart
stub (signatures only, no bodies).

- `project_directory`: (required) Absolute path to the Dart/Flutter project
  directory (the folder containing pubspec.yaml). Used to resolve the package
  version from pubspec.lock and to locate the package_config.json for analysis.
- `package`: (required) The package name (e.g. "http", "provider").
- `library_uri`: (required) The library URI to target, e.g.
  "package:http/http.dart".
- `class`: (required) The class, mixin, or extension name to target (e.g.
  "Client").

## `inspector` server

Tools for launching, inspecting, and interacting with a running Flutter app.

Session lifecycle: call run_app first to get a session_id; pass it to all other
tools. Call close_app when done.

Recommended workflow for UI changes:

1. Edit Dart source files.
2. reload — applies changes without losing app state. Use full_restart: true
   only when state must reset (e.g. initState changes).
3. screenshot — visually confirm the change. Do this proactively; don't assume
   the edit was correct.
4. If the screenshot reveals a problem, use inspect_layout (for sizing/overflow
   issues) or evaluate (for runtime state).

Debugging layout issues:

- inspect_layout with no widget_id starts from the root.
- Widget IDs appear in flutter.error log events — use them to jump directly to
  the failing widget.
- Increase subtree_depth to see deeper into the tree.

Orientation:

- get_route shows the current navigator stack with screen widget names and
  source locations. Use this to confirm which screen is active before inspecting
  or editing.
- get_semantics lists visible, interactive nodes with their IDs. Pass node IDs
  directly to 'tap' and 'set_text'.

Flutter.Error events are forwarded automatically as MCP log warnings — no
polling needed. They include widget IDs for use with inspect_layout.

### `inspector:run_app`

```
run_app(working_directory, [target, device])
```

Builds and launches the Flutter app. Returns a session ID required by all other
tools. Call this first before inspecting, screenshotting, or evaluating.
Flutter.Error events from the running app are automatically forwarded as MCP log
warnings — no polling needed.

- `working_directory`: (required) The Flutter project directory to launch.
- `target`: The main entry point to launch (e.g. lib/main.dart). Defaults to the
  project default.
- `device`: Optional device ID override. When omitted, auto-selects the best
  available device (prefers desktop for fast builds). Only pass this if the user
  requests a specific device.

### `inspector:reload`

```
reload(session_id, [full_restart])
```

Applies source file changes to a running Flutter app. Call this after editing
Dart files, before taking a screenshot or inspecting layout. Prefer hot reload
for iterative changes; use hot restart (full_restart: true) when state needs to
be fully reset.

- `session_id`: (required) The session ID returned by run_app.
- `full_restart`: If true, performs a hot restart instead of a hot reload.
  Defaults to false.

### `inspector:take_screenshot`

```
take_screenshot(session_id, [pixel_ratio])
```

Captures a PNG screenshot of the running Flutter app. Use proactively after a
reload to visually confirm UI changes are correct, and when diagnosing layout or
rendering issues. Root widget bounds are resolved automatically. Note: only the
Flutter view is captured — native system UI such as platform share sheets,
permission dialogs, or OS-level overlays will not appear in the screenshot even
if visible on screen.

- `session_id`: (required) The session ID returned by run_app.
- `pixel_ratio`: Device pixel ratio for the screenshot. Higher values produce
  sharper images. Defaults to 1.0.

### `inspector:inspect_layout`

```
inspect_layout(session_id, [widget_id, subtree_depth])
```

Use when debugging layout issues, overflow errors, or unexpected widget sizing.
Returns constraints, size, flex parameters, and children for a widget. Omit
widget_id to start from the root. Widget IDs are included in flutter.error log
events and in the output of prior inspect calls — use them to drill into a
specific node. Increase subtree_depth to see deeper child layout.

- `session_id`: (required) The session ID returned by run_app.
- `widget_id`: The widget ID to inspect. Omit to start from the root widget.
- `subtree_depth`: How many levels of children to include. Defaults to 1.

### `inspector:evaluate`

```
evaluate(session_id, expression, [library_uri])
```

Evaluates a Dart expression on the running app's main isolate and returns the
result as a string. Use for binding-layer and platform-layer state not visible
in the widget tree: FlutterView properties (physicalSize, devicePixelRatio),
MediaQueryData, or any runtime value. By default runs in the root library scope
(main.dart), so top-level declarations and globals are in scope. Pass
library_uri to evaluate in a different library scope — for example,
"package:flutter/src/widgets/widget_inspector.dart" makes RendererBinding,
SemanticsNode, CheckedState, and Tristate available.

- `session_id`: (required) The session ID returned by run_app.
- `expression`: (required) The Dart expression to evaluate. Must produce a value
  with a useful toString(). Example:
  "WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio.toString()"
- `library_uri`: Optional. The URI of the library scope in which to evaluate the
  expression. Defaults to the app's root library (main.dart). Use
  "package:flutter/src/widgets/widget_inspector.dart" to access Flutter
  rendering and semantics APIs such as RendererBinding, SemanticsNode,
  CheckedState, and Tristate.

### `inspector:get_route`

```
get_route(session_id)
```

Returns the current navigator route stack with screen widget names and source
locations. Use this to confirm which screen is active before inspecting or
editing, or to answer "what screen is the app on?" questions. Enriches the stack
with the current go_router path when the app uses go_router.

- `session_id`: (required) The session ID returned by run_app.

### `inspector:navigate`

```
navigate(session_id, path)
```

Navigates the app to a go_router path. Calls GoRouter.go(path) on the running
app — no app modification required. Only works with apps that use go_router. Use
get_route first to see the current path and understand the app's route
structure. Example path: "/podcast/123".

- `session_id`: (required) The session ID returned by run_app.
- `path`: (required) The go_router path to navigate to. Must start with "/".
  Example: "/podcast/123".

### `inspector:get_semantics`

```
get_semantics(session_id)
```

Returns a flat list of visible semantics nodes from the running Flutter app.
Each node shows its role, ID, state flags, supported actions, label, and size.
Use this to find what is on screen and what can be interacted with. Node IDs
from this output can be passed directly to 'tap' and 'set_text'. Node IDs are
stable until the next hot reload or hot restart.

- `session_id`: (required) The session ID returned by run_app.

### `inspector:tap`

```
tap(session_id, [node_id, label])
```

Taps a widget by its semantics node ID or label. Dispatches a tap action via
SemanticsBinding.performSemanticsAction — no screen coordinates needed.

One of "node_id" or "label" must be provided. Prefer "node_id" when available
(faster — skips tree fetch). Use get_semantics first to see available nodes and
their IDs.

Note that this call relies on `action:tap` being present in the semantics node.

- `session_id`: (required) The session ID returned by run_app.
- `node_id`: The semantics node ID to tap. Shown as "id=N" in get_semantics
  output. Prefer this over "label" when you already know the ID.
- `label`: Tap the first visible node whose label contains this text
  (case-insensitive substring match). Use when you do not have a node ID.
  Ignored if "node_id" is provided.

### `inspector:set_text`

```
set_text(session_id, text, [node_id, label])
```

Sets the text content of a text field by its semantics node ID or label.
Dispatches SemanticsAction.setText — replaces the field's current content
entirely. No keyboard simulation needed. One of "node_id" or "label" must be
provided. Prefer "node_id" when available (faster — skips tree fetch). Semantics
node IDs and labels appear in get_semantics output. Tip: tap the field first
('tap') if the app requires focus before accepting text input. Note that this
call relies on `action:setText` being present in the semantics node.

- `session_id`: (required) The session ID returned by run_app.
- `text`: (required) The text to set. Replaces the field's current content.
- `node_id`: The semantics node ID of the text field. Shown as "id=N" in
  get_semantics output. Prefer this over "label" when you already know the ID.
- `label`: Set text in the first visible node whose label contains this text
  (case-insensitive substring match). Use when you do not have a node ID.
  Ignored if "node_id" is provided.

### `inspector:close_app`

```
close_app(session_id)
```

Stops a running Flutter app and releases its session.

- `session_id`: (required) The session ID returned by run_app.
