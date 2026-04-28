# Gemini CLI plugin info

## Implementation specific files

- gemini-extension.json
- .gemini-extension/GEMINI.md

The `contextFileName` field sets the agent context file (equivalent to
CLAUDE.md). Not certain that we need it for this plugin.

```json
"contextFileName": ".gemini-extension/GEMINI.md"
```

## MCP servers

Variable for the plugin root: `${extensionPath}`

`command` is a shell string — spaces and inline args are supported. `cwd` should
be set to `${extensionPath}` so that `dart run` resolves the pubspec correctly.

```json
"mcpServers": {
  "packages": {
    "command": "dart run ${extensionPath}/bin/packages_mcp.dart",
    "cwd": "${extensionPath}"
  }
}
```

## Distribution

Distribution is via direct install.

```
gemini extensions install https://github.com/devoncarew/flutter-slipstream
```

## Running locally

Load the Gemini CLI extension locally:

```sh
gemini extensions link /path/to/flutter-slipstream
```

Verify with `gemini --list-extensions`.
