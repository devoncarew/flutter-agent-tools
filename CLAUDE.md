# flutter-slipstream

A tool that makes AI coding agents more effective when working on Dart and
Flutter projects. Distributed as a Claude Code plugin and a Gemini CLI
extension. Addresses two core failure modes: agents using outdated APIs due to
training cutoff limitations, and agents being unable to observe a running
Flutter app.

## Key Conventions

- Inspector MCP server entry point: `bin/inspector_mcp.dart`; logic:
  `lib/src/inspector/inspector_mcp.dart`. Declared in
  `.claude-plugin/plugin.json`.
- Dart API MCP server entry point: `bin/packages_mcp.dart`; logic:
  `lib/src/shorthand/packages_mcp.dart`. Declared in
  `.claude-plugin/plugin.json`.
- Package currency hook: `bin/deps_check_claude.dart`, invoked via
  `scripts/deps_check_claude.sh --mode=pub-add|pubspec-guard`. Configured in
  `.claude-plugin/plugin.json`.
- Hooks receive tool input as JSON on stdin; exit 0 always (warnings only —
  hard-blocking is reserved for cases where proceeding would be clearly wrong).
- Use `${CLAUDE_PLUGIN_ROOT}` for all paths in hook commands — never hardcode.
- Fail open on infrastructure errors (network timeout, etc.): don't block the
  agent over tooling failures.
- Plugin version is tracked in `.claude-plugin/plugin.json` (not `pubspec.yaml`,
  which has `publish_to: none`).

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

Session lifecycle: `run_app` starts a session; `close_app` ends it. Only one
session is active at a time — `run_app` silently stops any existing session
before launching.

- `run_app` — builds and launches a Flutter app; `working_directory` must be an
  absolute path
- `reload` — hot reload (`full_restart: false`, default) or hot restart
  (`full_restart: true`)
- `get_output` — drains the output buffer; call after reload and interaction
  tools to see app stdout, Flutter errors, and route changes
- `take_screenshot` — captures a PNG screenshot via the inspector protocol
- `inspect_layout` — returns the widget layout tree; `widget_id` omitted → root
- `evaluate` — evaluates an arbitrary Dart expression on the main isolate
- `get_route` — navigator stack with screen widget names and source locations;
  enriched with the current router path when `slipstream_agent` is installed
- `navigate` — navigates to a route path via the registered router adapter;
  requires `slipstream_agent` companion
- `get_semantics` — flat list of visible semantics nodes (role, ID, state,
  actions, label, position/size); uses `ext.slipstream.get_semantics` with
  screen-space coordinates when companion is present
- `perform_semantic_action` — dispatches a semantics action (tap, longPress,
  setText, …) by semantics node ID or label; no companion required
- `perform_tap` — taps a widget by finder
  (byKey/byType/byText/bySemanticsLabel); requires `slipstream_agent` companion
- `perform_set_text` — sets text field content by finder; requires companion
- `perform_scroll` — scrolls a Scrollable by fixed pixels; requires companion
- `perform_scroll_until_visible` — scrolls until a target widget is visible;
  requires companion
- `close_app` — stops the running app and releases its session

### slipstream_agent companion (`package:slipstream_agent`)

An optional dependency apps can install for richer instrumentation. When present
(detected via `ext.slipstream.ping`), the inspector server uses in-process
service extensions instead of evaluate-based fallbacks:

- `ext.slipstream.perform_action` — finder-based
  tap/set_text/scroll/scroll_until_visible
- `ext.slipstream.navigate` — router-adapter navigation
- `ext.slipstream.get_route` — current route path from the router adapter
- `ext.slipstream.get_semantics` — semantics nodes with screen-space coordinates
- `ext.slipstream.windowResized` event — forwarded as `[window] WxH` log
- `ext.slipstream.routeChanged` event — forwarded as `[route] /path` log

Typed wrappers for all companion calls live in
`lib/src/inspector/flutter_service_extensions.dart` (`slipstreamTap`,
`slipstreamSetText`, etc.). Never call `callSlipstreamExtension` directly from
tool code.

## Current Status

- Plugin scaffold: done
- Package currency hook (`bin/deps_check_claude.dart`): functional — discontinued
  check, old major version check, pubspec-guard mode all implemented
- packages MCP server: functional — `package_summary`, `library_stub`, and
  `class_stub` all implemented
- inspector MCP server: functional — all tools above implemented and working
- `slipstream_agent` companion detection and event forwarding: implemented
- `get_output` tool: pull-based output buffer for app stdout, Flutter errors,
  and route changes; `_serverLog` is diagnostic-only (not agent-visible)

## Development

```sh
# Run all tests:
dart test

# Test the deps-check hook manually:
echo '{"tool_name":"Bash","tool_input":{"command":"flutter pub add http"}}' \
  | dart run bin/deps_check_claude.dart --mode=pub-add

# Load the plugin locally:
claude --plugin-dir /path/to/flutter-slipstream

# Regenerate the README command tables:
dart run tool/generate_readme.dart
```

## Design Reference

See `docs/DESIGN.md` for the full architecture and planned tool designs.

See `docs/inspector.md` for a Flutter runtime inspection guide for AI agents.
