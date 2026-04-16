# Flutter Slipstream

Generated documentation on Slipstream's MCP servers, and their instructions and
tools.

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
  directory (the folder containing pubspec.yaml). Used to locate
  .dart_tool/package_config.json for package resolution and analysis. Run
  `dart pub get` first if the config is missing.
- `package`: (required) The package name (e.g. "http", "provider").

### `packages:library_stub`

```
library_stub(project_directory, package, library_uri)
```

Returns the full public API for one library as a Dart stub (signatures only, no
bodies).

- `project_directory`: (required) Absolute path to the Dart/Flutter project
  directory (the folder containing pubspec.yaml). Used to locate
  .dart_tool/package_config.json for package resolution and analysis. Run
  `dart pub get` first if the config is missing.
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
  directory (the folder containing pubspec.yaml). Used to locate
  .dart_tool/package_config.json for package resolution and analysis. Run
  `dart pub get` first if the config is missing.
- `package`: (required) The package name (e.g. "http", "provider").
- `library_uri`: (required) The library URI to target, e.g.
  "package:http/http.dart".
- `class`: (required) The class, mixin, or extension name to target (e.g.
  "Client").

## `inspector` server

Tools for launching, inspecting, and interacting with a running Flutter app.

Session lifecycle: call run_app first to launch the app; call close_app when
done. Only one app session can be active at a time — calling run_app while an
app is already running will stop the previous app first.

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
- Widget IDs appear in flutter.error log output — use them to jump directly to
  the failing widget.
- Increase subtree_depth to see deeper into the tree.

Orientation:

- get_route shows the current navigator stack with screen widget names and
  source locations. Use this to confirm which screen is active before inspecting
  or editing.
- get_semantics lists visible, interactive nodes with their IDs. Pass node IDs
  directly to 'perform_semantic_action'.
- If the app has slipstream_agent installed, use 'perform_tap',
  'perform_set_text', 'perform_scroll', or 'perform_scroll_until_visible'
  instead of 'perform_semantic_action' — these support byKey/byType/byText
  finders and do not require semantics annotations.

After reload or any interaction tool, call get_output to see app stdout, Flutter
errors, and route changes since the last call.

### `inspector:run_app`

```
run_app(working_directory, [target, device])
```

Builds and launches the Flutter app. Call this first before inspecting,
screenshotting, or evaluating. If an app is already running it is stopped and
replaced. Flutter.Error events from the running app are automatically forwarded
as MCP log warnings — no polling needed.

- `working_directory`: (required) The Flutter project directory to launch.

Note that this should be an absolute path.

- `target`: The main entry point to launch (e.g. lib/main.dart). Defaults to the
  project default.
- `device`: Optional device ID override. When omitted, auto-selects the best
  available device (prefers desktop for fast builds). Only pass this if the user
  requests a specific device.

### `inspector:reload`

```
reload([full_restart])
```

Applies source file changes to a running Flutter app. Call this after editing
Dart files, before taking a screenshot or inspecting layout. Prefer hot reload
for iterative changes; use hot restart (full_restart: true) when state needs to
be fully reset.

- `full_restart`: If true, performs a hot restart instead of a hot reload.
  Defaults to false.

### `inspector:get_output`

```
get_output()
```

Returns buffered app output and runtime events since the last call (or the last
reload/restart).

Call this after reload, after interaction tools (perform_tap, perform_set_text,
etc.), and after run_app to check for errors or unexpected output. Calling this
clears the buffer.

Output is prefixed by source:

- [app] print() / debugPrint() output from the app
- [stdout] other process stdout
- [flutter.error] framework errors; widget IDs usable with inspect_layout
- [route] navigation events (requires slipstream_agent companion)

### `inspector:take_screenshot`

```
take_screenshot([pixel_ratio])
```

Captures a PNG screenshot of the running Flutter app. Use proactively after a
reload to visually confirm UI changes are correct, and when diagnosing layout or
rendering issues. Root widget bounds are resolved automatically. Note: only the
Flutter view is captured — native system UI such as platform share sheets,
permission dialogs, or OS-level overlays will not appear in the screenshot even
if visible on screen.

- `pixel_ratio`: Device pixel ratio for the screenshot. Higher values produce
  sharper images. Defaults to 1.0.

### `inspector:inspect_layout`

```
inspect_layout([widget_id, subtree_depth])
```

Use when debugging layout issues, overflow errors, or unexpected widget sizing.
Returns constraints, size, flex parameters, and children for a widget. Omit
widget_id to start from the root. Widget IDs are included in flutter.error log
events and in the output of prior inspect calls — use them to drill into a
specific node. Increase subtree_depth to see deeper child layout.

- `widget_id`: The widget ID to inspect. Omit to start from the root widget.
- `subtree_depth`: How many levels of children to include. Defaults to 1.

### `inspector:evaluate`

```
evaluate(expression, [library_uri])
```

Evaluates a Dart expression on the running app's main isolate and returns the
result as a string. Use for binding-layer and platform-layer state not visible
in the widget tree: FlutterView properties (physicalSize, devicePixelRatio),
MediaQueryData, or any runtime value. By default runs in the root library scope
(main.dart), so top-level declarations and globals are in scope. Pass
library_uri to evaluate in a different library scope — for example,
"package:flutter/src/widgets/widget_inspector.dart" makes RendererBinding,
SemanticsNode, CheckedState, and Tristate available.

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
get_route()
```

Returns the current navigator route stack with screen widget names and source
locations. Use this to confirm which screen is active before inspecting or
editing, or to answer "what screen is the app on?" questions. Enriches the stack
with the current router path when the slipstream_agent companion is installed
with a router adapter.

### `inspector:navigate`

```
navigate(path)
```

Navigates the app to a route path. Requires the slipstream_agent companion
package with a router adapter registered via SlipstreamAgent.init(router:
GoRouterAdapter(appRouter)).

Supports any routing library for which an adapter exists: GoRouter, AutoRouter,
Beamer, or a custom adapter. Use get_route first to see the current path and
understand the app's route structure.

Example path: "/podcast/123".

- `path`: (required) The route path to navigate to. Must start with "/".
  Example: "/podcast/123".

### `inspector:perform_tap`

```
perform_tap(finder, finder_value)
```

Taps a widget located by a finder. Synthesizes a pointer down/up event at the
widget's center — triggers GestureDetector.onTap, InkWell.onTap, and any other
gesture recognizers.

Finders: byKey (ValueKey string), byType (widget type name, e.g.
"ElevatedButton"), byText (Text widget content), bySemanticsLabel (Semantics
widget label).

Requires the slipstream_agent companion package. Without it, use
perform_semantic_action with action "tap" instead.

- `finder`: (required) How to find the widget: "byKey", "byType", "byText", or
  "bySemanticsLabel".
- `finder_value`: (required) The value to match against the chosen finder.

### `inspector:perform_set_text`

```
perform_set_text(finder, finder_value, text)
```

Sets the text content of a text field located by a finder. Replaces the field's
current content and fires the field's onChanged callback. Note:
TextInputFormatters are not applied since text is set directly without going
through the input pipeline.

Finders: byKey (ValueKey string), byType (widget type name, e.g. "TextField"),
byText (Text widget content), bySemanticsLabel (Semantics widget label).

Tip: call perform_tap on the field first if the app requires focus before
accepting text input.

Requires the slipstream_agent companion package. Without it, use
perform_semantic_action with action "setText" instead.

- `finder`: (required) How to find the widget: "byKey", "byType", "byText", or
  "bySemanticsLabel".
- `finder_value`: (required) The value to match against the chosen finder.
- `text`: (required) The text to set. Replaces the field's current content.

### `inspector:perform_scroll`

```
perform_scroll(finder, finder_value, direction, pixels)
```

Scrolls a Scrollable widget by a fixed number of logical pixels. The finder
locates the Scrollable (e.g. ListView, SingleChildScrollView) directly. Clamped
to the scroll extent bounds.

Finders: byKey (ValueKey string), byType (widget type name, e.g. "ListView"),
byText (Text widget content), bySemanticsLabel (Semantics widget label).

To bring a specific widget into view, use perform_scroll_until_visible instead.

Requires the slipstream_agent companion package.

- `finder`: (required) How to find the Scrollable widget: "byKey", "byType",
  "byText", or "bySemanticsLabel".
- `finder_value`: (required) The value to match against the chosen finder.
- `direction`: (required) Scroll direction: "up", "down", "left", or "right".
- `pixels`: (required) Number of logical pixels to scroll.

### `inspector:perform_scroll_until_visible`

```
perform_scroll_until_visible(finder, finder_value, scroll_finder, scroll_finder_value)
```

Scrolls a Scrollable widget until a target widget is visible in the viewport.
Two finders are required: one to locate the target widget, and one to locate the
Scrollable that contains it.

Finders for both: byKey (ValueKey string), byType (widget type name), byText
(Text widget content), bySemanticsLabel (Semantics label).

Example: scroll a ListView (scroll_finder="byType",
scroll_finder_value="ListView") until item_42 is visible (finder="byKey",
finder_value="item_42").

Requires the slipstream_agent companion package.

- `finder`: (required) How to find the target widget: "byKey", "byType",
  "byText", or "bySemanticsLabel".
- `finder_value`: (required) The value to match against the target finder.
- `scroll_finder`: (required) How to find the Scrollable: "byKey", "byType",
  "byText", or "bySemanticsLabel".
- `scroll_finder_value`: (required) The value to match against the scroll
  finder.

### `inspector:get_semantics`

```
get_semantics()
```

Returns a flat list of visible semantics nodes from the running Flutter app.
Each node shows its role, ID, state flags, supported actions, label, and size.
Use this to find what is on screen and what can be interacted with. Node IDs
from this output can be passed directly to 'perform_semantic_action'. Node IDs
are stable until the next hot reload or hot restart.

### `inspector:perform_semantic_action`

```
perform_semantic_action(action, [node_id, label, value])
```

Dispatches a semantics action on a widget by its semantics node ID or label.
Works without the slipstream_agent companion package, but requires the target
widget to have a semantics node.

Common actions:

- tap — tap a button, list item, or any tappable widget
- setText — set text field content; provide "value" with the text
- longPress — long-press a widget
- focus — move keyboard focus to an input field
- scrollUp / scrollDown — scroll a scrollable widget
- increase / decrease — adjust a slider or stepper

One of "node_id" or "label" must be provided. Prefer "node_id" when available
(faster — skips tree fetch). Use get_semantics first to see available nodes and
their IDs.

For apps with the slipstream_agent companion installed, prefer perform_tap,
perform_set_text, perform_scroll, or perform_scroll_until_visible — they support
byKey/byType/byText finders and do not require semantics annotations.

- `action`: (required) The SemanticsAction to dispatch. Common values: tap,
  setText, longPress, focus, scrollUp, scrollDown, increase, decrease.
- `node_id`: The semantics node ID. Shown as "id=N" in get_semantics output.
  Prefer this over "label" when you already know the ID.
- `label`: Dispatch to the first visible node whose label contains this text
  (case-insensitive substring match). Ignored if "node_id" is provided.
- `value`: Required for the setText action. Replaces the field's current content
  entirely. Ignored for other actions.

### `inspector:close_app`

```
close_app()
```

Stops the running Flutter app and releases its session.
