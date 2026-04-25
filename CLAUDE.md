# flutter-slipstream

A Claude Code plugin, Gemini CLI extension, and GitHub Copilot extension that
makes AI coding agents more effective when working on Dart and Flutter projects.
Feature complete. See `docs/index.md` for the full documentation index.

## Key Conventions

- Hooks receive tool input as JSON on stdin; always exit 0 (warnings only). Fail
  open on infrastructure errors — never block the agent over tooling failures.
- Use `${CLAUDE_PLUGIN_ROOT}` for all paths in hook commands — never hardcode.
- Plugin version is tracked in three manifests: `.claude-plugin/plugin.json`,
  `gemini-extension.json`, and `.github/plugin/plugin.json` (not `pubspec.yaml`,
  which has `publish_to: none`). Run `dart run tool/repo.dart check-versions` to
  validate they're in sync before opening a release PR.

## MCP Tools

For the full tool reference (packages server, inspector server, and
slipstream_agent companion extensions), see the `mcp-tools` skill.

## Development

```sh
dart test
dart analyze && dart format .
dart run tool/repo.dart generate-docs   # regenerate README command tables

# Test the deps-check hook manually:
echo '{"tool_name":"Bash","tool_input":{"command":"flutter pub add http"}}' \
  | node scripts/deps_check.js --agent=claude --mode=pub-add
```
