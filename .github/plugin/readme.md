# GitHub Copilot plugin info

## Implementation specific files

- .github/plugin/plugin.json

## MCP servers

Variable for the plugin root: `${PLUGIN_ROOT}`

MCP servers require `"type": "local"`. The `command` field must be the
executable name only (no shell expansion — spaces are not supported). Arguments
go in `args`, which is a required field for schema validation even when empty.

No `cwd` field is supported. For `dart run <absolute-path>`, this is fine
because Dart resolves the pubspec by walking up from the script file's location.

```json
"mcpServers": {
  "packages": {
    "type": "local",
    "command": "dart",
    "args": ["run", "${PLUGIN_ROOT}/bin/packages_mcp.dart"]
  }
}
```

## Hooks

Event name: `preToolUse` (camel case). Each hook specifies `bash` and
`powershell` fields for cross-platform support. There is no per-hook matcher —
the hook fires for all tool uses.

```json
"hooks": {
  "preToolUse": [
    {
      "type": "command",
      "bash": "node ${PLUGIN_ROOT}/scripts/deps_check.js --agent=copilot",
      "powershell": "node ${PLUGIN_ROOT}/scripts/deps_check.js --agent=copilot"
    }
  ]
}
```
