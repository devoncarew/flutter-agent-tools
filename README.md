# flutter-agent-tools

A Claude Code plugin that helps AI coding agents write better Dart and Flutter
code.

## Tools

### Dependency Health Hook

A `PreToolUse` hook that intercepts `flutter pub add` / `dart pub add` commands
and validates packages against pub.dev before they are added. Blocks
discontinued packages and suggests official replacements.

Requires: `curl`, `jq`

### pubspec.yaml Guard (stub)

A `PreToolUse` hook that intercepts direct `Write`/`Edit` operations on
`pubspec.yaml` and validates newly-added dependencies. Not yet implemented.

### Package API Inspector (planned)

An MCP command that returns a token-efficient Markdown summary of a package's
public API — without requiring the agent to read raw source from `.pub-cache`.

### Flutter UI Agent (planned)

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
| `flutter_evaluate` | Evaluates a Dart expression on the running app's main isolate and returns the result as a string. Use for binding-layer and platform-layer state not visible in the widget tree: FlutterView properties (physicalSize, devicePixelRatio), MediaQueryData, Navigator state, or any runtime value. Runs in the root library scope, so top-level declarations and globals are in scope. Example: "WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio.toString()" |
| `flutter_query_ui` | Returns a high-level description of what is currently on screen in the running Flutter app. Use to orient before navigating to a specific app state, to confirm a change took effect, or to understand the current route before drilling into layout details. Modes: "semantics" — flat list of visible, interactive nodes (labels, roles, bounding boxes); "widget_tree" — summary widget tree filtered to user-written widgets; "route" — current route name and navigator state. |
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
git clone https://github.com/devoncarew/flutter-agent-tools
cd flutter-agent-tools
chmod +x scripts/*.sh

# Test the hook manually:
echo '{"tool_name":"Bash","tool_input":{"command":"flutter pub add http"}}' \
  | ./scripts/dep_health_check.sh
```

## Links

- [flight_check issue #17](https://github.com/devoncarew/flight_check/issues/17)
  — Flutter UI agent use cases
- [flight_check issue #2](https://github.com/devoncarew/flight_check/issues/2) —
  pub outdated hook generalization
- [Playwright MCP](https://playwright.dev/docs/getting-started-mcp) —
  inspiration for Tool 3
