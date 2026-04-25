# Contributing

Contributions welcome! For anything but a non-trivial change, please start a
discussion with an issue first.

## Development

Load the Claude Code plugin locally:

```
claude --plugin-dir /path/to/flutter-slipstream
```

Load the Gemini CLI extension locally:

```sh
gemini extensions link /path/to/flutter-slipstream
```

Run all tests:

```sh
dart test
```

Regenerate the README command tables:

```sh
dart run tool/repo.dart generate-docs
```

## Pull requests

- Keep changes focused; one logical change per PR.
- Run `dart format .` and `dart test` before submitting.
- PR descriptions should be concise: a one-sentence summary plus a bullet list
  of the main changes.

## Code style

- Follow standard Dart conventions (`dart format`, `dart analyze`).
- Prefer explicit types on class fields.
- Hooks: exit 0 always; hard-blocking is reserved for cases where proceeding
  would be clearly wrong, and fail open on infrastructure errors (network timeouts, etc.).

## Releasing

Releases are triggered automatically when a version-bump PR lands on `main`. To
prepare a release:

1. Update `CHANGELOG.md` — rename the `X.Y.Z-wip` section to `X.Y.Z` and add a
   new `X+1.Y.Z-wip` section at the top.
2. Bump the `version` field in `.claude-plugin/plugin.json`,
   `gemini-extension.json`, and `.github/plugin/plugn.json` to match.
3. Open a PR. CI will detect the version bump, label it `release-pr`, and post a
   comment confirming the version that will be published.
4. Once the PR lands, CI creates a GitHub release tagged `vX.Y.Z` with the
   matching changelog section as the release notes.

`dart run tool/repo.dart check-versions` validates that the file version infomation is
in sync.
