# Cursor plugin info

## Implementation files

- .cursor-plugin/plugin.json

## MCP servers

Variable for the plugin root: `${CURSOR_PLUGIN_ROOT}`

`command` is a shell string — spaces and inline args are supported. No `cwd`
field is supported; `dart run <absolute-path>` resolves the pubspec by walking
up from the script file's location, so this is fine.

```json
"mcpServers": {
  "packages": {
    "command": "dart run ${CURSOR_PLUGIN_ROOT}/bin/packages_mcp.dart"
  }
}
```

## Hooks

Event name: `preToolUse`. Matchers use Cursor tool names (`Shell`, `Write`,
etc.).

### preToolUse

Called before any tool execution. Input JSON (stdin):

```json
{
  "tool_name": "Shell",
  "tool_input": { "command": "npm install", "working_directory": "/project" },
  "tool_use_id": "abc123",
  "cwd": "/project",
  "model": "claude-sonnet-4-20250514",
  "agent_message": "Installing dependencies..."
}
```

Expected output JSON (stdout):

```json
{
  "permission": "allow",
  "user_message": "<shown in client when denied>",
  "agent_message": "<sent to agent when denied>",
  "updated_input": { "command": "npm ci" }
}
```
