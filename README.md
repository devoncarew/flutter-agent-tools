# flutter-agent-tools

A Claude Code plugin that helps AI coding agents write better Dart and Flutter
code.

## Tools

### Package Currency Hook

Two `PreToolUse` hooks that help agents use current, well-maintained packages.
Fires when adding packages via `flutter pub add` / `dart pub add` or by directly
editing `pubspec.yaml`. Emits advisory warnings and lets the agent decide; never
hard-blocks.

Checks performed:

- **Discontinued:** warns with the official replacement if one is listed.
- **Old major version:** warns when the requested constraint targets an older
  major than what pub.dev currently publishes (e.g. `http:^0.13.0` vs latest
  `1.x`).
- **Not found:** warns if the package name doesn't exist on pub.dev.

### Package API Retrieval and Summarization (planned)

An MCP server (`dart-api`) that retrieves and summarizes a package's public API
directly from the local pub cache — giving agents accurate, version-matched
signatures without reading raw source or relying on training-data summaries.

### Flutter UI Agent

MCP commands for building, launching, and introspecting a running Flutter app at
runtime: query semantic elements, inject text, trigger taps, and pull unhandled
exceptions from the Dart VM Service.

<!-- flutter commands -->
<!-- prettier-ignore-start -->
| Command | Description |
|---------|-------------|
| `flutter_launch_app` | Builds and launches the Flutter app. Returns a session ID required by all other flutter_* tools. Call this first before inspecting, screenshotting, or evaluating. Flutter.Error events from the running app are automatically forwarded as MCP log warnings — no polling needed. |
| `flutter_reload` | Applies source file changes to a running Flutter app. Call this after editing Dart files, before taking a screenshot or inspecting layout. Prefer hot reload for iterative changes; use hot restart (full_restart: true) when state needs to be fully reset. |
| `flutter_take_screenshot` | Captures a PNG screenshot of the running Flutter app. Use proactively after a reload to visually confirm UI changes are correct, and when diagnosing layout or rendering issues. Root widget bounds are resolved automatically. |
| `flutter_inspect_layout` | Use when debugging layout issues, overflow errors, or unexpected widget sizing. Returns constraints, size, flex parameters, and children for a widget. Omit widget_id to start from the root. Widget IDs are included in flutter.error log events and in the output of prior inspect calls — use them to drill into a specific node. Increase subtree_depth to see deeper child layout. |
| `flutter_evaluate` | Evaluates a Dart expression on the running app's main isolate and returns the result as a string. Use for binding-layer and platform-layer state not visible in the widget tree: FlutterView properties (physicalSize, devicePixelRatio), MediaQueryData, or any runtime value. Runs in the root library scope, so top-level declarations and globals are in scope. Example: "WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio.toString()" |
| `flutter_query_ui` | Returns a high-level description of what is currently on screen in the running Flutter app. Use to orient before navigating to a specific app state, to confirm a change took effect, or to understand the current route before drilling into layout details. Modes: "route" — current route name and navigator stack (use this for "what screen/route is the app on?" questions); "semantics" — flat list of visible, interactive nodes (labels, roles, bounding boxes); "widget_tree" — summary widget tree filtered to user-written widgets. |
| `flutter_close_app` | Stops a running Flutter app and releases its session. |
<!-- prettier-ignore-end -->
<!-- flutter commands -->

## Installation

```sh
# Install from a marketplace (once published):
/plugin install flutter-agent-tools

# Or test locally:
claude --plugin-dir </path/to>/flutter-agent-tools
```

## Development

```sh
# To Test the deps-check hook manually:
echo '{"tool_name":"Bash","tool_input":{"command":"flutter pub add http"}}' \
  | dart run bin/deps_check.dart --mode=pub-add
```

## Links

- [flight_check issue #2](https://github.com/devoncarew/flight_check/issues/2) —
  pub outdated hook generalization
- [flight_check issue #17](https://github.com/devoncarew/flight_check/issues/17)
  — Flutter UI agent use cases
- [Playwright MCP](https://playwright.dev/docs/getting-started-mcp) —
  inspiration for Tool 3
