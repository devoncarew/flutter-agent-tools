# Claude Code plugin info

## Implementation specific files

- .claude-plugin/plugin.json

## MCP servers

Variable for the plugin root: `${CLAUDE_PLUGIN_ROOT}`

`command` is a shell string — spaces and inline args are supported. `cwd` is
also supported and should be set to `${CLAUDE_PLUGIN_ROOT}` so that `dart run`
resolves the pubspec correctly.

```json
"mcpServers": {
  "packages": {
    "command": "dart run ${CLAUDE_PLUGIN_ROOT}/bin/packages_mcp.dart",
    "cwd": "${CLAUDE_PLUGIN_ROOT}"
  }
}
```

## Distribution

Distribution is via the https://github.com/devoncarew/slipstream marketplace.

```
claude plugin marketplace add devoncarew/slipstream
claude plugin install flutter-slipstream@slipstream
```

## Running locally

Load the Claude Code plugin locally:

```
claude --plugin-dir /path/to/flutter-slipstream
```

Verify with `claude plugins list`.
