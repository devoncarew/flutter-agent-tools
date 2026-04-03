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
├── hooks/
│   └── hooks.json               # PreToolUse hook configuration
├── lib/
│   ├── mcp_server.dart          # Library export
│   └── src/
│       └── mcp_server.dart      # FlutterAgentServer (MCPServer + ToolsSupport)
├── scripts/
│   ├── dep_health_check.sh      # Bash hook: validates packages before flutter pub add
│   └── pubspec_guard.sh         # Write/Edit hook: guards direct pubspec.yaml edits (stub)
├── analysis_options.yaml
├── pubspec.yaml
├── CLAUDE.md
├── DESIGN.md
└── README.md
```

## Components

### Hooks (shell scripts, implemented)

- `dep_health_check.sh`: PreToolUse hook on Bash. Intercepts `flutter pub add`
  / `dart pub add`, queries pub.dev, blocks discontinued packages, warns on
  stale ones. Requires `curl` and `jq`.
- `pubspec_guard.sh`: PreToolUse hook on Write/Edit targeting pubspec.yaml.
  Currently a no-op stub.

### MCP Server (Dart, scaffolded)

A Dart CLI package at the repo root. Entry point is `bin/mcp_server.dart`;
server logic lives in `lib/src/mcp_server.dart`. Exposes MCP tools for the
Package API Inspector and Flutter UI Agent. Declared in `plugin.json` under
`mcpServers`.

## Key Conventions

- Hook scripts receive tool input as JSON on stdin; exit 0 to allow, exit 1 to block.
- Use `${CLAUDE_PLUGIN_ROOT}` for all paths in hook commands — never hardcode.
- Fail open on infrastructure errors (missing `curl`/`jq`, network timeout):
  don't block the agent over tooling issues.
- The MCP server is a Dart CLI package. Run via `dart run flutter_agent_tools:mcp_server`.

## Current Status

- Plugin scaffold: done
- `dep_health_check.sh`: functional (pub.dev validation, discontinuation check, age heuristic)
- `pubspec_guard.sh`: stub only
- MCP server: scaffolded (echo tool only; real tools not yet implemented)

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
