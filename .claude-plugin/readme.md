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

## Hooks

Event name: `PreToolUse` (Pascal case). Hooks are nested — the outer array
holds `{ matcher, hooks[] }` objects; each inner hook has `type`, `if`,
`command`, `description`, and optionally `cwd`.

The `if` field takes a pattern of the form `ToolName(glob)`, e.g.
`Bash(flutter pub add *)`. `matcher` is the tool name that gates whether the
hook list is even consulted.

```json
"hooks": {
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "if": "Bash(some command pattern *)",
          "command": "node ${CLAUDE_PLUGIN_ROOT}/scripts/your_hook.js",
          "cwd": "${CLAUDE_PLUGIN_ROOT}"
        }
      ]
    }
  ]
}
```
