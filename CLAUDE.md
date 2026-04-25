# flutter-slipstream

A Claude Code plugin, Gemini CLI extension, and GitHub Copilot extension that
makes AI coding agents more effective when working on Dart and Flutter projects.
Feature complete. See [index.md](docs/index.md) for the full documentation
index.

## MCP Tools

For the full tool reference (packages server, inspector server, and
slipstream_agent companion extensions), see the `mcp-tools` skill
([SKILL.md](.claude/skills/mcp-tools/SKILL.md)).

## Key Conventions

- Hooks receive tool input as JSON on stdin; always exit 0 (warnings only). Fail
  open on infrastructure errors — never block the agent over tooling failures.
- The plugin manifests are: `.claude-plugin/plugin.json`,
  `gemini-extension.json`, and `.github/plugin/plugin.json`.

## Development

```sh
dart test
dart analyze && dart format .
dart run tool/repo.dart generate-docs   # regenerate README command tables
```
