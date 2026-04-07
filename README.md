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
| `flutter_launch_app` | Builds and launches the Flutter app. |
| `flutter_reload` | Applies source file changes to a running Flutter app. |
| `flutter_take_screenshot` | Captures a PNG screenshot of the running Flutter app. |
| `flutter_inspect_layout` | Use when debugging layout issues, overflow errors, or unexpected widget sizing. |
| `flutter_evaluate` | Evaluates a Dart expression on the running app's main isolate and returns the result as a string. |
| `flutter_query_ui` | Returns a high-level description of what is currently on screen in the running Flutter app. |
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
