# flutter-agent-tools

A Claude Code plugin that makes AI coding agents more effective when working on
Dart and Flutter projects. It addresses two core failure modes: agents using
outdated APIs due to training cutoff limitations, and agents being unable to
observe a running Flutter app.

## Key Conventions

- MCP server entry point: `bin/mcp_server.dart`; logic:
  `lib/src/mcp_server.dart`. Declared in `.claude-plugin/plugin.json`.
- Dep check hook: `bin/dep_check.dart`, invoked via
  `scripts/start_dep_check.sh --mode=pub-add|pubspec-guard`. Configured in
  `hooks/hooks.json`.
- Hooks receive tool input as JSON on stdin; exit 0 always (warnings only —
  hard-blocking is reserved for cases where proceeding would be clearly wrong).
- Use `${CLAUDE_PLUGIN_ROOT}` for all paths in hook commands — never hardcode.
- Fail open on infrastructure errors (network timeout, etc.): don't block the
  agent over tooling failures.
- The MCP server is a Dart CLI package: `dart run bin/mcp_server.dart`.

## Registered MCP Tools

- `flutter_launch_app` — builds and launches a Flutter app, returns a session ID
- `flutter_reload` — hot reload or hot restart a running app
- `flutter_take_screenshot` — captures a PNG screenshot via the inspector
  protocol
- `flutter_inspect_layout` — returns the layout tree for a widget (or root)
- `flutter_evaluate` — evaluates an arbitrary Dart expression on the main
  isolate
- `flutter_query_ui` - supports different modes to get information of what is
  currently on screen
- `flutter_close_app` — stops a running app and releases its session

## Current Status

- Plugin scaffold: done
- Dep health hook (`bin/dep_check.dart`): functional — discontinued check,
  old major version check, pubspec-guard mode all implemented
- MCP server: functional — launch, reload, close, screenshot, inspect layout,
  evaluate, and query_ui (route mode with go_router path enrichment) all working
- Flutter.Error events are pushed to agents with widget IDs for use with
  `flutter_inspect_layout`

## Development

```sh
# Test the dep-check hook directly:
echo '{"tool_name":"Bash","tool_input":{"command":"flutter pub add http"}}' \
  | dart run bin/dep_check.dart --mode=pub-add

# Load the plugin locally:
claude --plugin-dir /path/to/flutter-agent-tools
```

## Design Reference

See `DESIGN.md` for the full architecture and planned tool designs.

See `docs/inspector.md` for a Flutter runtime inspection guide for AI agents.
