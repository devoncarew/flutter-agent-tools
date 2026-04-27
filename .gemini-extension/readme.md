# Gemini CLI plugin info

## Implementation specific files

- gemini-extension.json
- .gemini-extension/GEMINI.md

## MCP servers

Variable for the plugin root: `${extensionPath}`

`command` is a shell string — spaces and inline args are supported. `cwd`
should be set to `${extensionPath}` so that `dart run` resolves the pubspec
correctly.

```json
"mcpServers": {
  "packages": {
    "command": "dart run ${extensionPath}/bin/packages_mcp.dart",
    "cwd": "${extensionPath}"
  }
}
```

The `contextFileName` field sets the agent context file (equivalent to
CLAUDE.md):

```json
"contextFileName": ".gemini-extension/GEMINI.md"
```

## Hooks

Hooks live in a separate file (e.g. `hooks/hooks-gemini.json`), not inline in
`gemini-extension.json`.

Event name: `BeforeTool` (not `PreToolUse`). Matchers are tool name patterns
(pipe-separated for alternation, e.g. `write_file|replace`), using Gemini CLI's
own tool names rather than MCP tool names.

```json
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": "run_shell_command",
        "hooks": [
          {
            "name": "my-hook",
            "type": "command",
            "command": "node ${extensionPath}/scripts/your_hook.js"
          }
        ]
      }
    ]
  }
}
```
