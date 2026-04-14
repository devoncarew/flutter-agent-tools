# Flutter Slipstream Extension

This extension provides tools for Dart/Flutter development:
- **`packages` MCP server**: Token-efficient package API summarization from `.pub-cache`.
- **`inspector` MCP server**: Runtime UI inspection and interaction for Flutter apps.

## `packages` Workflow
1. Use `package_summary` to identify public libraries and exported names.
2. Use `library_stub` to get full API signatures for a library.
3. Use `class_stub` to drill into specific classes when needed.
*This avoids reading large implementation files and provides accurate signatures.*

## `inspector` Workflow
1. **Launch**: `run_app` to start the Flutter app.
2. **Iterate**:
   - Edit source files.
   - `reload` (hot reload) to apply changes.
   - `take_screenshot` to visually confirm.
3. **Debug**:
   - `inspect_layout` for layout/overflow issues (use widget IDs from `flutter.error` logs).
   - `get_route` to see the current screen stack.
   - `get_semantics` to find interactive elements by label or ID.
   - `evaluate` for runtime state (e.g., `MediaQuery`).
4. **Interact**: Use `perform_tap`, `perform_set_text`, `perform_scroll`, or `perform_navigate`.
5. **Finish**: `close_app` to release resources.

*Flutter.Error events are automatically logged with widget IDs to help diagnose issues.*
