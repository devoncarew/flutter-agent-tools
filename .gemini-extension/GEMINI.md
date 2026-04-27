# Flutter Slipstream Extension

This extension provides tools for Dart/Flutter development:

- **`packages` MCP server**: Token-efficient package API summarization from
  `.pub-cache`.
- **`inspector` MCP server**: Runtime UI inspection and interaction for Flutter
  apps.

## `packages` Workflow

1. Use `package_summary` to identify public libraries and exported names.
2. Use `library_stub` to get full API signatures for a library.
3. Use `class_stub` to drill into specific classes when needed. _This avoids
   reading large implementation files and provides accurate signatures._

## Adding Package Dependencies

Use `flutter pub add <package>` (or `dart pub add`) rather than editing
`pubspec.yaml` directly. After every `pub add`, read the full output before
proceeding:

- **`(discontinued replaced by X)`** on a package you just added: remove it and
  add `X` instead. A summary line `N package(s) are discontinued` confirms the
  count.
- **`(X.Y.Z available)`** on a package you just added: you've pinned an older
  version. Run `flutter pub outdated` and check the `Latest` column. If a direct
  dependency is behind by a major version, update the constraint (e.g.
  `flutter pub add 'lints:^6.0.0'`).
- Transitive dependency gaps are generally not actionable — note them but don't
  block on them.

If you edit `pubspec.yaml` directly instead of using `pub add`, run
`flutter pub get` immediately after and apply the same rules to the output.

## `inspector` Workflow

1. **Launch**: `run_app` to start the Flutter app.
2. **Iterate**:
   - Edit source files.
   - `reload` (hot reload) to apply changes.
   - `take_screenshot` to visually confirm.
3. **Debug**:
   - `inspect_layout` for layout/overflow issues (use widget IDs from
     `flutter.error` logs).
   - `get_route` to see the current screen stack.
   - `get_semantics` to find interactive elements by label or ID.
   - `evaluate` for runtime state (e.g., `MediaQuery`).
4. **Interact**: Use `perform_tap`, `perform_set_text`, `perform_scroll`, or
   `navigate`.
5. **Finish**: `close_app` to release resources.
