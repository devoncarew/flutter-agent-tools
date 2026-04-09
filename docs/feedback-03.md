# Plugin Feedback: flutter-slipstream (Session 3)

**Date:** 2026-04-08  
**Task:** Build a Flutter widget showcase app from a hello-world template, using
provider, go_router, and flutter_animate. Test both MCP servers (inspector +
packages) iteratively.

---

## Work Log

1. Explored the existing hello-world project and loaded all tool schemas.
2. Added dependencies to pubspec.yaml: `provider`, `go_router`,
   `flutter_animate`, `shared_preferences`, `url_launcher`.
3. Attempted to use `package_summary` for `go_router` and `flutter_animate` —
   both calls failed (see Bugs).
4. Created the full app structure:
   - `lib/providers/theme_provider.dart` — ChangeNotifier backed by
     shared_preferences
   - `lib/main.dart` — MaterialApp.router with GoRouter + ChangeNotifierProvider
   - `lib/screens/home_screen.dart` — 3-column responsive grid with
     flutter_animate staggered entries
   - `lib/screens/buttons_screen.dart` — all Material 3 button variants
   - `lib/screens/inputs_screen.dart` — TextField, Checkbox, Switch, Slider,
     Radio, Dropdown
   - `lib/screens/cards_screen.dart` — Card variants, ListTile, Chips, Badges,
     Progress, Dividers
   - `lib/screens/animations_screen.dart` — flutter_animate: fade, slide, scale,
     shimmer, chained, staggered, flip
   - `lib/screens/typography_screen.dart` — all M3 text styles + color role
     swatches
   - `lib/screens/dialogs_screen.dart` — AlertDialog, SimpleDialog, BottomSheet,
     SnackBar, Pickers, Banner
   - `lib/screens/colors_screen.dart` — full color scheme role list with hex
     values
5. Ran `run_app` — launched cleanly on macOS in ~seconds.
6. Iterative loop: edit → `reload` → `take_screenshot` to verify. Caught and
   fixed:
   - Overflow errors (cards 12px too short) — fixed by reading the screenshot
   - Used `context.go()` initially; spotted missing back button in screenshot,
     switched to `context.push()`
   - New `/colors` route didn't appear after hot reload (expected — GoRouter is
     a `final`); used `full_restart`
7. Used `get_semantics` + `tap` to test the dark/light theme toggle.
8. Navigated across all 7 screens using `navigate` to verify each one visually.

---

## What Worked Well

### `run_app`

Fast and reliable. Chose macOS automatically (best for iteration speed). Session
ID handoff to all other tools is clean. The whole flow from "write code" to "app
is running" took only a few seconds.

### `take_screenshot`

This is the killer feature. Being able to visually verify every change without
leaving the agent loop is transformative. The `pixel_ratio: 2` option produces
sharp, readable output. I used it after nearly every `reload` and caught real
issues (overflow errors, missing back button) that I would otherwise have had to
guess at.

### `reload` (hot reload + hot restart)

Hot reload worked reliably for code-level changes. The reminder in the response
— _"semantics node IDs are reassigned after each reload"_ — is excellent UX; it
prevents a whole class of stale-ID bugs. Hot restart worked correctly when I
needed state reset (new GoRouter routes).

### `navigate` with go_router path

This is a standout feature. Being able to call `navigate(path: "/buttons")` and
immediately screenshot the result is far better than having to simulate taps
through the home screen every time. It respects the app's router, and the
go_router path enrichment in `get_route` is a thoughtful integration.

### `get_semantics` + `tap` by node_id

Reliable once I had a node ID. The flat list format with role, ID, actions,
label, and size is easy to parse. Good for interaction testing that goes beyond
visual verification.

### `inspect_layout`

Not heavily used this session (no persistent layout bugs), but the tool is
well-designed — starting from root and drilling by widget ID is a natural
workflow that mirrors how Flutter developers think about the tree.

---

## Bugs

### 1. `package_summary` throws "Missing arguments" on every call — critical bug

Both calls failed with a server-side Dart exception
(`ToolContext.validateParams`) even though the required parameters
(`project_directory`, `package`) were provided correctly:

```
mcp__plugin_flutter-slipstream_packages__package_summary(
  project_directory: "/Users/devoncarew/projects/devoncarew/showcase",
  package: "go_router"
)
→ ToolException: Missing arguments
```

The full stack trace was returned as the error message, which is useful for
debugging but shouldn't be user-visible. The packages server appears to have a
validation bug where it rejects valid inputs. This is a significant gap — the
packages tools are explicitly designed to give accurate, version-matched API
signatures, which is exactly what an agent needs when using an unfamiliar
package. Without them, I fell back on training-data knowledge (which may be
subtly wrong for newer API versions like go_router 14.x).

**Impact:** High. The entire `packages` MCP server was non-functional this
session.

---

### 2. `tap` by label fails for `IconButton` with only a tooltip

```
tap(label: "Toggle theme")
→ error: no visible semantics node with label containing "Toggle theme"
```

The button was declared as:

```dart
IconButton(
  tooltip: 'Toggle theme',
  icon: Icon(...),
  onPressed: ...,
)
```

In `get_semantics`, this appeared as `[button id=188 action:tap action:focus]`
with no label. Flutter's `IconButton` does wrap the tooltip in a `Semantics`
widget and sets `label` to the tooltip value — but either the macOS
accessibility tree doesn't expose it, or the plugin's semantics extraction
doesn't surface it. The workaround (fetch semantics, find the unlabeled button
by position) works, but it's fragile.

**Impact:** Medium. Icon-only buttons are common in Flutter apps, and they
almost always use `tooltip` as their only accessible name.

---

## Suggestions for Improvement

### 1. Fix `package_summary` (critical)

The packages server validation is rejecting valid calls. Even if only
`library_stub` and `class_stub` worked, they'd provide enormous value for
unfamiliar packages. This should be top priority.

### 2. `navigate` should indicate route-not-found

When `navigate(path: "/colors")` was called before the route existed (before hot
restart), the tool returned `"Navigated to /colors"` successfully, but the app
showed a "Page Not Found" error screen. The tool had no way to know the
navigation failed. It would help to either:

- Check if the resulting route matches the requested path (via `get_route`)
- Return a warning if a GoException is thrown

### 3. `get_semantics` should expose tooltip as label for icon buttons

When an `IconButton` has a `tooltip` but no explicit `Semantics` label, the
tooltip value should be surfaced in the semantics output. This would make
`tap(label: "Toggle theme")` work as expected and remove the need to
cross-reference node IDs.

### 4. Warn when hot reload may be insufficient

When I added a new `GoRoute` to a `final _router` variable and called `reload`,
the route silently wasn't registered. The tool could detect that a top-level
`final` with a complex initializer was modified and suggest a hot restart. Even
a generic note like _"If new routes or providers aren't appearing, try
full_restart: true"_ in the response would save time.

### 5. `take_screenshot` — option to highlight overflow errors

Flutter's overflow error banners are visible in screenshots, which is already
very helpful. But it would be even better if the tool could return a flag like
`has_overflow_errors: true` alongside the image, so an agent can check
programmatically without needing to visually scan every screenshot.

### 6. `run_app` — expose build/compile errors cleanly

If the Dart code has compile errors, the tool returns a raw Flutter error log.
The signal (what failed and where) is buried in noise. A structured error format
with file, line, and message extracted from the compiler output would make it
much easier to act on.

### 7. `library_stub` / `class_stub` — consider pre-flight check

Since `package_summary` is broken this session, I can't speak to the others. But
for future: it would be useful if these tools returned a clear "package not in
pub cache" error vs. "package found but library not found" — the distinction
matters for knowing whether to run `flutter pub get` first.

---

## Overall Assessment

The **inspector server** is genuinely excellent. The `run_app` → `reload` →
`take_screenshot` loop is fast, ergonomic, and closes the gap between "agent
writes code" and "agent sees the result." The `navigate` tool with go_router
integration is a standout feature. In a real development session, this plugin
would meaningfully reduce the number of back-and-forth cycles needed to build
correct UI.

The **packages server** was completely non-functional due to the
`package_summary` bug, so I can't evaluate it fairly. Fixing that bug should be
the immediate priority — the concept (version-matched API stubs from the local
pub cache) is exactly right, and it would fill the largest gap agents face with
Flutter: confidently using packages they don't know well.
