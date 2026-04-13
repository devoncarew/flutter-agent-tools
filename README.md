# Flutter Slipstream

A Claude Code plugin that makes AI coding agents more effective for Dart and
Flutter projects.

AI agents working on Dart and Flutter run into two recurring problems. First,
their training data has a cutoff — they'll reach for discontinued packages, pin
outdated major versions, or produce subtly wrong API signatures that compile
only after a correction loop. Second, Flutter development is inherently visual
and stateful, and agents have no way to see a running app: they can't observe a
layout failure, verify that a state change took effect, or confirm that a
navigation worked.

This plugin addresses both. It adds hooks that catch stale package choices
before they land in `pubspec.yaml`, an MCP tool that retrieves accurate package
API signatures directly from the local pub cache, and a suite of MCP commands
for launching, inspecting, and interacting with a running Flutter app.

## Installation

```sh
# Test locally:
claude --plugin-dir </path/to>/flutter-slipstream
```

## Tools

### Package currency hook

A `PreToolUse` hook that fires when an agent adds a package via
`flutter pub add` / `dart pub add` or edits `pubspec.yaml` directly. Emits
advisory warnings and lets the agent decide; never hard-blocks.

Checks:

- **Discontinued:** warns with the official replacement if one is listed.
- **Old major version:** warns when the constraint targets an older major than
  what pub.dev currently publishes (e.g. `http:^0.13.0` vs latest `1.x`).
- **Not found:** warns if the package name doesn't exist on pub.dev.

### Package API retrieval (`packages`)

Retrieves a package's public API surface directly from the local pub cache and
returns it as a compact Dart stub — signatures only, no bodies, no private
members. Agents get accurate, version-matched API information without reading
raw source files or relying on training-data summaries.

<!-- packages -->
<!-- prettier-ignore-start -->
| Command | Description |
|---------|-------------|
| `package_summary` | Returns API summaries for Dart or Flutter packages; start here to orient on an unfamiliar package. |
| `library_stub` | Returns the full public API for one library as a Dart stub (signatures only, no bodies). |
| `class_stub` | Returns the public API for a single named class, mixin, or extension as a Dart stub (signatures only, no bodies). |
<!-- prettier-ignore-end -->
<!-- packages -->

### Flutter UI agent (`inspector`)

MCP commands for launching, inspecting, and interacting with a running Flutter
app. Gives agents a [Playwright](https://playwright.dev/)-style interface to the
running app: take screenshots, inspect the widget tree, evaluate arbitrary Dart
expressions, and observe runtime errors with widget IDs.

<!-- inspector -->
<!-- prettier-ignore-start -->
| Command | Description |
|---------|-------------|
| `run_app` | Builds and launches the Flutter app. |
| `reload` | Applies source file changes to a running Flutter app. |
| `take_screenshot` | Captures a PNG screenshot of the running Flutter app. |
| `inspect_layout` | Use when debugging layout issues, overflow errors, or unexpected widget sizing. |
| `evaluate` | Evaluates a Dart expression on the running app's main isolate and returns the result as a string. |
| `get_route` | Returns the current navigator route stack with screen widget names and source locations. |
| `navigate` | Navigates the app to a route path. |
| `perform_tap` | Taps a widget located by a finder. |
| `perform_set_text` | Sets the text content of a text field located by a finder. |
| `perform_scroll` | Scrolls a Scrollable widget by a fixed number of logical pixels. |
| `perform_scroll_until_visible` | Scrolls a Scrollable widget until a target widget is visible in the viewport. |
| `get_semantics` | Returns a flat list of visible semantics nodes from the running Flutter app. |
| `perform_semantic_action` | Dispatches a semantics action on a widget by its semantics node ID or label. |
| `close_app` | Stops the running Flutter app and releases its session. |
<!-- prettier-ignore-end -->
<!-- inspector -->

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
