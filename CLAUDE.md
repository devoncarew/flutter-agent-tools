# flutter-slipstream

A Claude Code plugin, Gemini CLI extension, and GitHub Copilot extension that
makes AI coding agents more effective when working on Dart and Flutter projects.
Feature complete. See [index.md](docs/index.md) for the full documentation
index.

## MCP Tools

For the full tool reference (packages server, inspector server, and
slipstream_agent companion extensions), see
[docs/packages_mcp.md](docs/packages_mcp.md) and
[docs/inspector_mcp.md](docs/inspector_mcp.md).

## Key Conventions

- The plugin manifests are: `.claude-plugin/plugin.json`,
  `gemini-extension.json`, and `.github/plugin/plugin.json`. All three plus
  `CHANGELOG.md` must be bumped together on release — see
  [CONTRIBUTING.md](CONTRIBUTING.md).
- Inspector tools are one-class-per-file in `lib/src/inspector/tools/`,
  implementing `InspectorTool`. Packages tools follow the same pattern in
  `lib/src/shorthand/tools/`.

## Development

```sh
dart test                              # unit tests; test/scripts/ runs full MCP servers as subprocesses
dart analyze && dart format .
dart run tool/repo.dart generate-docs  # regenerate README command tables
```
