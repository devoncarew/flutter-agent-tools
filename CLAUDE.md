# flutter-agent-tools

A Claude Code plugin that makes AI coding agents more effective when working on
Dart and Flutter projects. It addresses two core failure modes: agents using
outdated APIs due to training cutoff limitations, and agents being unable to
observe a running Flutter app.

## Key Conventions

- Inspector MCP server entry point: `bin/inspector_mcp.dart`; logic:
  `lib/src/inspector/inspector_server.dart`. Declared in
  `.claude-plugin/plugin.json`.
- Shorthand MCP server entry point: `bin/shorthand_mcp.dart`; logic:
  `lib/src/shorthand/shorthand_server.dart`. Declared in
  `.claude-plugin/plugin.json`.
- Package currency hook: `bin/deps_check.dart`, invoked via
  `scripts/deps_check.sh --mode=pub-add|pubspec-guard`. Configured in
  `hooks/hooks.json`.
- Hooks receive tool input as JSON on stdin; exit 0 always (warnings only —
  hard-blocking is reserved for cases where proceeding would be clearly wrong).
- Use `${CLAUDE_PLUGIN_ROOT}` for all paths in hook commands — never hardcode.
- Fail open on infrastructure errors (network timeout, etc.): don't block the
  agent over tooling failures.

## Registered MCP Tools

### dart-api server (`bin/shorthand_mcp.dart`)

- `package_info` — returns API summaries for Dart/Flutter packages from the
  local pub cache. `kind` parameter: `package_summary` (default),
  `library_stub`, `class_stub`.

### flutter-inspect server (`bin/inspector_mcp.dart`)

- `flutter_launch_app` — builds and launches a Flutter app, returns a session ID
- `flutter_reload` — hot reload or hot restart a running app
- `flutter_take_screenshot` — captures a PNG screenshot via the inspector
  protocol
- `flutter_inspect_layout` — returns the layout tree for a widget (or root)
- `flutter_evaluate` — evaluates an arbitrary Dart expression on the main
  isolate
- `flutter_get_route` — returns the navigator stack with screen names and
  source locations; enriches with go_router path when available
- `flutter_navigate` — navigates to a go_router path via `GoRouter.go()`
- `flutter_get_semantics` — returns a flat list of visible semantics nodes
  (role, ID, state, actions, label, size); node IDs usable with flutter_tap
- `flutter_tap` — tap an element by semantics node ID or label
- `flutter_close_app` — stops a running app and releases its session

## Current Status

- Plugin scaffold: done
- Package currency hook (`bin/deps_check.dart`): functional — discontinued
  check, old major version check, pubspec-guard mode all implemented
- dart-api MCP server: functional — `package_summary`, `library_stub`, and
  `class_stub` all implemented
- flutter-inspect MCP server: functional — launch, reload, close, screenshot,
  inspect layout, evaluate, get_route (with go_router path enrichment),
  navigate, get_semantics, and tap all working
- Flutter.Error events are pushed to agents with widget IDs for use with
  `flutter_inspect_layout`

## Development

```sh
# Test the deps-check hook directly:
echo '{"tool_name":"Bash","tool_input":{"command":"flutter pub add http"}}' \
  | dart run bin/deps_check.dart --mode=pub-add

# Load the plugin locally:
claude --plugin-dir /path/to/flutter-agent-tools
```

## Design Reference

See `DESIGN.md` for the full architecture and planned tool designs.

See `docs/inspector.md` for a Flutter runtime inspection guide for AI agents.
