# flutter-agent-tools

A Claude Code plugin that makes AI coding agents more effective when working on
Dart and Flutter projects. It addresses two core failure modes: agents using
outdated APIs due to training cutoff limitations, and agents being unable to
observe a running Flutter app.

## Project Structure

```
flutter-agent-tools/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest (name, version, MCP server declarations)
├── bin/
│   └── mcp_server.dart          # MCP server entry point
├── docs/
│   ├── inspector.md             # Flutter runtime inspection guide for AI agents
│   └── inspector_sample.json    # Sample inspector protocol traffic
├── hooks/
│   └── hooks.json               # PreToolUse hook configuration
├── lib/
│   ├── mcp_server.dart          # Library export
│   └── src/
│       ├── diagnostics_node.dart        # DiagnosticsNode wire representation
│       ├── flutter_run_session.dart     # flutter run --machine subprocess manager
│       ├── flutter_service_extensions.dart  # VM service extension wrappers
│       └── mcp_server.dart              # FlutterAgentServer (MCPServer + ToolsSupport)
├── scripts/
│   ├── dep_health_check.sh      # Bash hook: validates packages before flutter pub add
│   └── pubspec_guard.sh         # Write/Edit hook: guards direct pubspec.yaml edits (stub)
├── test/
│   ├── mcp_server_test.dart
│   └── test_utils.dart
├── tool/
│   └── generate_readme.dart
├── analysis_options.yaml
├── pubspec.yaml
├── .prettierrc
├── CLAUDE.md
├── DESIGN.md
└── README.md
```

## Components

### Hooks (shell scripts, implemented)

- `dep_health_check.sh`: PreToolUse hook on Bash. Intercepts `flutter pub add` /
  `dart pub add`, queries pub.dev, blocks discontinued packages, warns on stale
  ones. Requires `curl` and `jq`.
- `pubspec_guard.sh`: PreToolUse hook on Write/Edit targeting pubspec.yaml.
  Currently a no-op stub.

### MCP Server (Dart, implemented)

A Dart CLI package at the repo root. Entry point is `bin/mcp_server.dart`;
server logic lives in `lib/src/mcp_server.dart`. Declared in `plugin.json` under
`mcpServers`.

The server manages `flutter run --machine` subprocesses via `FlutterRunSession`,
connects to the VM service via `package:vm_service`, and exposes Flutter
inspector extensions through `FlutterServiceExtensions`.

**Registered MCP tools:**

- `flutter_launch_app` — builds and launches a Flutter app, returns a session ID
- `flutter_perform_reload` — hot reload or hot restart a running app
- `flutter_close_app` — stops a running app and releases its session
- `flutter_take_screenshot` — captures a PNG screenshot via the inspector
  protocol
- `flutter_debug_paint` — gets or sets the debug paint overlay

## Key Conventions

- Hook scripts receive tool input as JSON on stdin; exit 0 to allow, exit 1 to
  block.
- Use `${CLAUDE_PLUGIN_ROOT}` for all paths in hook commands — never hardcode.
- Fail open on infrastructure errors (missing `curl`/`jq`, network timeout):
  don't block the agent over tooling issues.
- The MCP server is a Dart CLI package. Run via
  `dart run flutter_agent_tools:mcp_server`.

## Current Status

- Plugin scaffold: done
- `dep_health_check.sh`: functional (pub.dev validation, discontinuation check,
  age heuristic)
- `pubspec_guard.sh`: stub only
- MCP server: functional — launch, reload, close, screenshot, and debug paint
  tools are implemented and working

## Development

```sh
# Test a hook directly:
echo '{"tool_name":"Bash","tool_input":{"command":"flutter pub add http"}}' \
  | ./scripts/dep_health_check.sh

# Load the plugin locally:
claude --plugin-dir /path/to/flutter-agent-tools

# Reload after changes (inside a Claude Code session):
/reload-plugins
```

## Design Reference

See `DESIGN.md` for the full architecture and planned tool designs.

See `docs/inspector.md` for a Flutter runtime inspection guide for AI agents.
