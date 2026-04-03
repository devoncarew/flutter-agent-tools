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
| Command | Description |
|---------|-------------|
| `flutter_launch_app` | Builds and launches the Flutter app, returning a session ID for use with subsequent flutter_* tools. |
| `flutter_perform_reload` | Hot reloads or hot restarts a running Flutter app. Prefer hot reload for iterative changes; use hot restart when state needs to be fully reset. |
| `flutter_close_app` | Stops a running Flutter app and releases its session. |
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

- [flight_check issue #17](https://github.com/devoncarew/flight_check/issues/17) —
  Flutter UI agent use cases
- [flight_check issue #2](https://github.com/devoncarew/flight_check/issues/2) —
  pub outdated hook generalization
- [Playwright MCP](https://playwright.dev/docs/getting-started-mcp) —
  inspiration for Tool 3
