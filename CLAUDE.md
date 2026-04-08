# flutter-toolkit

A Claude Code plugin that makes AI coding agents more effective when working on
Dart and Flutter projects. It addresses two core failure modes: agents using
outdated APIs due to training cutoff limitations, and agents being unable to
observe a running Flutter app.

## Key Conventions

- Inspector MCP server entry point: `bin/inspector_mcp.dart`; logic:
  `lib/src/inspector/inspector_mcp.dart`. Declared in
  `.claude-plugin/plugin.json`.
- Dart API MCP server entry point: `bin/packages_mcp.dart`; logic:
  `lib/src/shorthand/packages_mcp.dart`. Declared in
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

### packages server (`bin/packages_mcp.dart`)

- `package_summary` — version, entry-point import, README excerpt, public
  library list, and exported name groups; start here to orient on an unfamiliar
  package
- `library_stub` — full public API for one library as a Dart stub file
  (signatures only, no bodies); requires `library_uri`
- `class_stub` — stub for a single named class, mixin, or extension; requires
  `library_uri` and `class`

### inspector server (`bin/inspector_mcp.dart`)

- `run_app` — builds and launches a Flutter app, returns a session ID
- `reload` — hot reload or hot restart a running app
- `take_screenshot` — captures a PNG screenshot via the inspector protocol
- `inspect_layout` — returns the layout tree for a widget (or root)
- `evaluate` — evaluates an arbitrary Dart expression on the main isolate
- `get_route` — returns the navigator stack with screen names and source
  locations; enriches with go_router path when available
- `navigate` — navigates to a go_router path via `GoRouter.go()`
- `get_semantics` — returns a flat list of visible semantics nodes (role, ID,
  state, actions, label, size); node IDs usable with 'tap'
- `tap` — tap an element by semantics node ID or label
- `set_text` — set text field content by semantics node ID or label
- `close_app` — stops a running app and releases its session

## Current Status

- Plugin scaffold: done
- Package currency hook (`bin/deps_check.dart`): functional — discontinued
  check, old major version check, pubspec-guard mode all implemented
- packages MCP server: functional — `package_summary`, `library_stub`, and
  `class_stub` all implemented
- inspector MCP server: functional — launch, reload, close, take_screenshot,
  inspect layout, evaluate, get_route (with go_router path enrichment),
  navigate, get_semantics, and tap all working
- Flutter.Error events are pushed to agents with widget IDs for use with
  `inspect_layout`

## Development

```sh
# Test the deps-check hook directly:
echo '{"tool_name":"Bash","tool_input":{"command":"flutter pub add http"}}' \
  | dart run bin/deps_check.dart --mode=pub-add

# Load the plugin locally:
claude --plugin-dir /path/to/flutter-toolkit
```

## Design Reference

See `DESIGN.md` for the full architecture and planned tool designs.

See `docs/inspector.md` for a Flutter runtime inspection guide for AI agents.
