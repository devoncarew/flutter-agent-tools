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

## Distribution

- TODO: Investigate distribution via https://cursor.com/marketplace (official?)
  vs https://cursor.directory/ (community?).
- TODO: https://cursor.com/marketplace/publish

## Running locally

Plugin are loaded from ~/.cursor/plugins. For fast iteration, symlink your
plugin repository:

```
ln -s /path/to/flutter-slipstream ~/.cursor/plugins/flutter-slipstream
```

Cursor seems to share some config locations with Claude?

Edit (or create) the registration file at
`~/.claude/plugins/installed_plugins.json` and add an entry for your local
plugin:

```json
{
  "plugins": {
    "flutter-slipstream@local": [
      {
        "scope": "user",
        "installPath": "/Users/yourname/.cursor/plugins/flutter-slipstream"
      }
    ]
  }
}
```
