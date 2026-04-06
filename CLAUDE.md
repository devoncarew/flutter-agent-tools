# flutter-agent-tools

A Claude Code plugin that makes AI coding agents more effective when working on
Dart and Flutter projects. It addresses two core failure modes: agents using
outdated APIs due to training cutoff limitations, and agents being unable to
observe a running Flutter app.

## Key Conventions

- MCP server entry point: `bin/mcp_server.dart`; logic:
  `lib/src/mcp_server.dart`. Declared in `.claude-plugin/plugin.json`.
- Hook scripts: `scripts/dep_health_check.sh` (Bash) and
  `scripts/pubspec_guard.sh` (Write/Edit on pubspec.yaml). Configured in
  `hooks/hooks.json`.
- Hook scripts receive tool input as JSON on stdin; exit 0 to allow, exit 1 to
  block.
- Use `${CLAUDE_PLUGIN_ROOT}` for all paths in hook commands — never hardcode.
- Fail open on infrastructure errors (missing `curl`/`jq`, network timeout):
  don't block the agent over tooling issues.
- The MCP server is a Dart CLI package:
  `dart run flutter_agent_tools:mcp_server`.

## Registered MCP Tools

- `flutter_launch_app` — builds and launches a Flutter app, returns a session ID
- `flutter_reload` — hot reload or hot restart a running app
- `flutter_close_app` — stops a running app and releases its session
- `flutter_take_screenshot` — captures a PNG screenshot via the inspector
  protocol
- `flutter_inspect_layout` — returns the layout tree for a widget (or root)
- `flutter_evaluate` — evaluates an arbitrary Dart expression on the main isolate

## Current Status

- Plugin scaffold: done
- `dep_health_check.sh`: functional (pub.dev validation, discontinuation check,
  age heuristic)
- `pubspec_guard.sh`: stub only
- MCP server: functional — launch, reload, close, screenshot, inspect layout,
  and evaluate tools are implemented and working
- Flutter.Error events are pushed to agents with widget IDs for use with
  `flutter_inspect_layout`

## Development

```sh
# Test a hook directly:
echo '{"tool_name":"Bash","tool_input":{"command":"flutter pub add http"}}' \
  | ./scripts/dep_health_check.sh

# Load the plugin locally:
claude --plugin-dir /path/to/flutter-agent-tools
```

## Design Reference

See `DESIGN.md` for the full architecture and planned tool designs.

See `docs/inspector.md` for a Flutter runtime inspection guide for AI agents.
