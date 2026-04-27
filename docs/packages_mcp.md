# Packages MCP Tool Reference

Server entry point: `bin/packages_mcp.dart`

Tools for querying Dart and Flutter package APIs from the local pub cache.
Source is `.pub-cache` — already downloaded, always matches the resolved version
in `pubspec.lock`, no network required.

## Typical call sequence

1. `package_summary` — orient: version, library list, exported names.
2. `library_stub` — get all signatures for one library.
3. `class_stub` — drill into a specific class.

## `package_summary(project_directory, package)`

Returns version, entry-point import, README excerpt, public library list, and
exported name groups for the main library.

- `project_directory` (required) — absolute path to the Dart/Flutter project
  (contains `pubspec.yaml`). Used to locate `.dart_tool/package_config.json`.
  Run `dart pub get` first if the config is missing.
- `package` (required) — package name (e.g. `"http"`, `"provider"`).

## `library_stub(project_directory, package, library_uri)`

Returns the full public API for one library as a Dart stub (signatures only, no
bodies). Mixin-contributed methods are inlined and attributed.

- `library_uri` (required) — e.g. `"package:http/http.dart"`.

## `class_stub(project_directory, package, library_uri, class)`

Returns the stub for a single named class, mixin, or extension, including
inherited and mixin-contributed members.

- `class` (required) — class/mixin/extension name (e.g. `"Client"`).
