# Copilot instructions for flutter-slipstream

This file helps Copilot/GitHub Code agents work effectively in this repository.

Build, test, and lint

- Install deps: dart pub get
- Run all tests: dart test
- Run a single test file: dart test test/path/to_test.dart
- Run a single test by name (regex): dart test -n "Test name regex"
- Static analysis: dart analyze
- Format code: dart format .
- Regenerate README docs: dart run tool/repo.dart generate-docs
- Test deps-check hook manually: echo
  '{"tool_name":"Bash","tool_input":{"command":"flutter pub add http"}}' \
   | dart run bin/deps_check_claude.dart --mode=pub-add

High-level architecture (short)

- Two Dart MCP servers:
  - packages (bin/packages_mcp.dart → lib/src/shorthand/packages_mcp.dart) •
    Provides package_summary, library_stub, class_stub by reading local
    .pub-cache
  - inspector (bin/inspector_mcp.dart → lib/src/inspector/inspector_mcp.dart) •
    Launches Flutter apps (auto device selection), supports run_app, reload,
    take_screenshot, inspect_layout, evaluate, get_route, get_semantics, and
    interaction helpers (tap, set_text, scroll). Uses the Dart VM service and
    the Flutter inspector protocol.
- Hooks and scripts:
  - Package-currency hook: bin/deps_check_claude.dart
    (scripts/deps_check_claude.sh)
  - Gemini hook variants in scripts/ and gemini-extension.json
- Companion package: package:slipstream_agent (optional but must be a regular
  dependency when installed) — enables richer finder-based interactions and
  router-aware navigation.

Key conventions and repo-specific patterns

- Versioning and plugin metadata:
  - Plugin/extension version is tracked in .claude-plugin/plugin.json and
    gemini-extension.json (not in pubspec.yaml). Keep them in sync.
  - Use dart run tool/repo.dart check-versions before opening release PRs.

- Hooks behavior:
  - Hooks accept JSON on stdin and always exit 0 (warnings only). They "fail
    open" on infra/network errors; do not hard-block agents.
  - Use ${CLAUDE_PLUGIN_ROOT} for paths in hook commands (do not hardcode).

- packages MCP outputs:
  - Prefer Dart stub outputs (signatures-only) to avoid token-heavy
    implementation dumps. Tools provided: package_summary → library_stub →
    class_stub (progressive detail).

- inspector MCP notes:
  - Auto-selects device (desktop matching host OS is preferred). When device_id
    is provided, it is passed through to flutter run.
  - get_route enriches output for go_router apps by extracting the current URI
    when InheritedGoRouter is present.
  - Semantics-based interactions work without the companion; finder-based
    interactions require package:slipstream_agent.

- Tests and style:
  - Use `dart test`, `dart analyze`, and `dart format .` in CI and locally.
  - analysis_options.yaml includes package:lints/recommended.yaml; follow lints.

Where to read more (authoritative source files)

- README.md — feature overview, tools, and usage notes
- docs/DESIGN.md — detailed architecture and design rationale
- CONTRIBUTING.md — development workflow, release process, and conventions
- lib/src/\* — implementation and concrete examples (inspector and packages
  servers)

Notes for agents

- When adding packages, invoke the package-currency hook flow (pub add or
  pubspec edit) and heed warnings about discontinued or old-major packages.
- Prefer requesting library_stub/class_stub rather than scanning .pub-cache
  implementation files to get accurate public APIs.
- For UI debugging, use inspector MCP commands (run_app → reload →
  take_screenshot → inspect_layout). Use get_semantics to discover interactable
  elements.

If this file already exists, suggest merging missing high-level details from
README.md and docs/DESIGN.md.

---

Generated from README.md, CONTRIBUTING.md, docs/DESIGN.md, and repo metadata.
