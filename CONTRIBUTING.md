# Contributing

## Development

```sh
# Run all tests:
dart test

# Test the deps-check hook manually:
echo '{"tool_name":"Bash","tool_input":{"command":"flutter pub add http"}}' \
  | dart run bin/deps_check.dart --mode=pub-add

# Load the plugin locally:
claude --plugin-dir /path/to/flutter-agent-tools

# Regenerate the README command tables:
dart run tool/generate_readme.dart
```

## Pull requests

- Keep changes focused; one logical change per PR.
- Run `dart format .` and `dart test` before submitting.
- PR descriptions should be concise: a one-sentence summary plus a bullet list
  of the main changes.

## Code style

- Follow standard Dart conventions (`dart format`, `dart analyze`).
- Prefer explicit types on class fields.
- Fail open on infrastructure errors (network timeouts, etc.) — don't block the
  agent over tooling failures.
- Hooks exit 0 always; hard-blocking is reserved for cases where proceeding
  would be clearly wrong.
