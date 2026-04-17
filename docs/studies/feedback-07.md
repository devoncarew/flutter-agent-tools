# Feedback: Flutter Slipstream Extension

## Pros

- **MCP Servers**: The `inspector` and `packages` servers are extremely
  powerful. Being able to query API signatures directly from the pub cache saves
  significant time and prevents "guessing" APIs.
- **Visual Verification**: `take_screenshot` is indispensable for a senior
  engineer to verify that the UI actually matches the intent, especially when
  working remotely or via CLI.
- **Interaction Tools**: `perform_set_text`, `perform_tap`, and `perform_scroll`
  work reliably with the `slipstream_agent` finders (`byKey`, `byText`), making
  automated UI testing feel natural.
- **Navigation Debugging**: `get_route` and `navigate` provide clear insights
  into the app's state, which is often hard to track in complex routing
  scenarios.

## Cons / Challenges

- **Hot Reload vs. Hot Restart**: Some structural changes (like updating
  `GoRouter` route builders) didn't always reflect immediately with a simple hot
  reload, requiring a `full_restart: true`. This is a known Flutter behavior but
  worth noting for this workflow.
- **Stale Semantics**: `get_semantics` can sometimes return stale information if
  called immediately after a navigation command before the UI transition
  completes.
- **Complex Finder Targets**: Tapping the `BottomNavigationBar` items by text
  was less reliable than using `navigate`, possibly due to the internal widget
  structure of the navigation bar.

## Bugs / Observations

- The standard `AppBar` drawer icon lacked a semantic label in the initial
  `get_semantics` output, requiring a guess or coordinate-based interaction
  (though I used the node ID).
- `perform_tap` on a `BottomNavigationBar` item by text didn't consistently
  trigger the `onTap` callback in this specific setup.

## Work Log

1. **Setup**: Configured `.gemini/settings.json` with appropriate tool
   permissions and trusted MCP servers.
2. **Dependencies**: Added `provider`, `go_router`, and `slipstream_agent` to
   `pubspec.yaml`.
3. **Scaffold**: Built the core shell with a `ThemeProvider` for light/dark mode
   and a `ShellRoute` for bottom navigation.
4. **Inputs Tab**: Created a screen with `TextField`, `Slider`, `Switch`, and
   `FilterChip`. Verified interactions.
5. **List Tab**: Created a scrollable list of 30 cards. Verified scrolling and
   item tapping (via snackbar).
6. **Form Tab**: Implemented a validated form with `TextFormField` and
   `Checkbox`. Verified submission logic.
7. **Navigation**: Verified jumping between tabs using `navigate` and
   interacting with the `Drawer`.
