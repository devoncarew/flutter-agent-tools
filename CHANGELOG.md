## 1.3.0-wip

- Fixed a race condition where app output emitted during startup was dropped;
  `run_app` now returns buffered output (build messages, initial route)
  alongside the launch result, and failure results include any output captured
  before the error. Session cleanup on process exit is now driven by the process
  `exitCode` future rather than the stdout `onDone` callback.
- Updated the plugin and extension descriptions.
- Updated the plugin and extension installation instructions.

## 1.2.0

- Addressed an issue where a 'restart' message could appear in the app under
  test at startup (and not just after a hot restart).
- Added `get_output` tool: returns buffered app stdout, Flutter errors, and
  route changes since the last call (or the last reload/restart), then clears
  the buffer. Replaces push-based MCP log notifications, which are not forwarded
  to agent context in Claude Code or Gemini CLI.

## 1.1.0

### `slipstream_agent` companion integration improvements

When `package:slipstream_agent` is installed in the target app, inspector tools
now report their activity to the companion's ghost overlay:

- `take_screenshot` suppresses the Flutter debug banner before capture and
  restores it afterward (via `ext.slipstream.overlays`)
- `reload` and hot restart log the operation with elapsed time
- `evaluate`, `inspect_layout`, and `perform_semantic_action` log their
  invocations with relevant context (expression snippet, widget ID, action
  target)
- Hot restart timing is handled correctly: the log fires after the companion
  re-registers its extensions post-restart

## 1.0.0

Initial public release.

### Package currency hook

- Warns when an agent adds a discontinued package (with official replacement if
  one is listed)
- Warns when a constraint targets an older major version than the current
  pub.dev release
- Warns when a package name is not found on pub.dev
- Fires on `flutter pub add` / `dart pub add` and on direct `pubspec.yaml` edits
- Always exits 0 — advisory only, never hard-blocks

### `packages` MCP server

- `package_summary` — version, entry-point import, README excerpt, public
  library list, and exported name groups
- `library_stub` — full public API for one library as a Dart stub file
  (signatures only, no bodies)
- `class_stub` — stub for a single named class, mixin, or extension

### `inspector` MCP server

- `run_app` — builds and launches a Flutter app; auto-selects the best available
  device (desktop > simulator > emulator > physical > web)
- `reload` — hot reload or hot restart
- `take_screenshot` — PNG screenshot via the inspector protocol
- `inspect_layout` — widget layout tree (subtree depth configurable)
- `evaluate` — arbitrary Dart expression on the main isolate
- `get_route` — navigator stack with screen widget names and source locations
- `navigate` — route navigation via registered router adapter (requires
  `slipstream_agent` companion)
- `get_semantics` — flat list of visible semantics nodes with role, ID, state,
  actions, label, and position
- `perform_semantic_action` — semantics action (tap, longPress, setText, …) by
  node ID or label
- `perform_tap` — finder-based tap (byKey/byType/byText/bySemanticsLabel);
  requires `slipstream_agent` companion
- `perform_set_text` — finder-based text field input; requires companion
- `perform_scroll` — scroll a Scrollable by fixed logical pixels; requires
  companion
- `perform_scroll_until_visible` — scroll until a target widget is in the
  viewport; requires companion
- `close_app` — stops the running app

### `slipstream_agent` companion integration

When `package:slipstream_agent` is installed in the target app, the inspector
server detects it via `ext.slipstream.ping` and activates enhanced mode:

- Finder-based widget interaction (byKey, byType, byText, bySemanticsLabel)
- Router-adapter navigation (GoRouter and others)
- Semantics nodes with accurate screen-space coordinates
- `[window]` log messages on resize
- `[route]` log messages on navigation
