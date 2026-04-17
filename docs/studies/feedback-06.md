# flutter-slipstream feedback

Session date: 2026-04-16 Task: build a small widget-showcase Flutter app while
exercising the plugin's two MCP servers (`inspector` and `packages`).

## Summary

The plugin worked well end-to-end — I was able to build, launch, and drive the
app entirely from the Claude session without ever dropping into a terminal for
`flutter run` or manual hot reload. The companion `slipstream_agent` package
paired with the byKey finders is the headline feature: it made interactions feel
like I was writing a widget test rather than scraping semantics.

## Pros

- **`run_app` was one call.** It auto-selected macOS and gave a mobile-sized
  viewport without needing a device flag or an emulator. The screenshot tool
  rendered a phone-shaped frame, which matched the "assume a phone screen" part
  of the task nicely.
- **`packages` server is a real quality-of-life win.** `package_summary` +
  `class_stub` let me confirm the exact shape of `SlipstreamAgent.init`,
  `GoRouterAdapter`, and `StatefulShellRoute.indexedStack` without reading
  pub.dev or guessing. For `slipstream_agent` specifically — a new package not
  in my training data — it was the only way to get accurate signatures.
- **`get_route` output is excellent.** Showing the go_router path, the root
  navigator stack, each per-branch navigator, and source file/line references
  made it trivial to confirm that `StatefulShellRoute` was wired up right.
- **byKey finders + `slipstream_agent` combo is ergonomic.** I put
  `ValueKey('inputs_text_field')` on widgets as I wrote them and then called
  `perform_set_text` / `perform_tap` against the same keys. No semantics
  annotations, no CSS-selector-style brittleness.
- **`perform_set_text` fires `onChanged`.** The Inputs tab echo updated live
  without needing a separate tap-to-focus step, which matched the tool's
  description accurately.
- **`navigate` via the router adapter is seamless.** `navigate("/form")` worked
  without having to chain through tab taps.
- **Good layering of tools.** Finder-based tools for apps that adopt
  `slipstream_agent`; semantic-based tools (`get_semantics`,
  `perform_semantic_action`) as a fallback when widgets have no keys. I used
  `perform_semantic_action` on `node_id=10` to open the Drawer (the hamburger is
  an unkeyed built-in IconButton) and it worked.
- **Screenshots are sharp and clearly framed.** PNG output rendered inline and
  was decisive for "is this right?" checks.

## Cons / bugs

- **`perform_scroll_until_visible` doesn't drive lazy list rebuilds.** On a
  `ListView.separated` with 40 items, both
  `perform_scroll_until_visible(byKey: list_item_30, ...)` and the same with
  `byText: "Item #30"` returned "no element found" — even though a manual
  `perform_scroll` with a pixel delta would bring the item in range. It looks
  like the finder is evaluated against the currently-built widget tree at the
  start of the call, rather than iteratively scrolling-then-searching. That's
  the exact scenario this tool should handle, since eager lists don't need it. A
  workaround exists (`perform_scroll` with enough pixels) but it undermines the
  tool's stated purpose.
- **Hamburger button has no semantic label.** `get_semantics` showed the leading
  AppBar IconButton as `[button id=10 ...]` with no label — I expected the
  default Flutter "Open navigation menu" tooltip to flow through as a semantic
  label. I had to fall back to the numeric node ID. Minor, but worth flagging:
  labels for built-in affordances are what make
  `perform_semantic_action(label: ...)` practical.
- **Per-branch navigators in `get_route` all say "navigator".** The output is:

      Navigator: navigator
      Route stack (1 entry):
        [1/1] InputsScreen ...
      Navigator: navigator
      Route stack (1 entry):
        [1/1] FormScreen ...

  Including the branch index (or the branch's `navigatorKey` debug-label if set)
  would help disambiguate, especially in apps with 4+ tabs.

- **`run_app` error was opaque.** My first launch failed with
  `null: (0) flutter run exited before app started.` — no stderr excerpt, no
  hint that the project has a compile error. I had to re-run `flutter analyze`
  manually to discover I'd forgotten an import. Forwarding the first few lines
  of stderr, or suggesting `flutter analyze`, would shorten the loop.
- **`get_output` doesn't replay on re-connect.** After `run_app`, the first
  `get_output` only showed `[route] /inputs` — no build output, no "Launched on
  device" line. Fine for steady-state, but makes the launch phase a bit of a
  black box.

## Areas for improvement (suggestions)

- Make `perform_scroll_until_visible` actually iterate: scroll step, re-check
  finder, stop when visible or scroll extent reached. Most Flutter lists are
  lazy, so this is the common case.
- In `get_route`, label the per-branch navigators with the branch index
  (`Navigator: branch 0 (Inputs)`) when the current route is under a
  `StatefulShellRoute`.
- Surface build/launch errors from `run_app` — at least stderr tail on failure.
  Right now the tool says "failed", but recovery requires leaving the tool
  ecosystem.
- Consider a `hot_reload_on_edit` or "edits pending" hint: I manually called
  `reload` after each edit, but the server already knows the target directory,
  so could offer a single `apply_edits` that reloads + screenshots. (Lower
  priority; explicit is also fine.)
- Document that `get_semantics` ignores `Tooltip` text. The "Open navigation
  menu" tooltip that Flutter sets on the Drawer hamburger does not become a
  semantics label in the output, which was surprising.

## Work log

1. Loaded the MCP tool schemas for both servers via ToolSearch.
2. Added deps with `flutter pub add provider go_router slipstream_agent`.
3. Wrote the app skeleton: `ThemeProvider` (ChangeNotifier), `HomeShell`
   (Drawer + NavigationBar + app-bar theme toggle), `InputsScreen`,
   `ListScreen`, `FormScreen`, `AboutScreen`, plus a `GoRouter` using
   `StatefulShellRoute.indexedStack`.
4. Initialized `SlipstreamAgent.init(router: GoRouterAdapter(router))` in
   `main`.
5. First `run_app` failed (opaque error). `flutter analyze` surfaced a missing
   `go_router` import in `main.dart`. Fixed and re-launched.
6. Verified Inputs tab: `perform_set_text` typed "hello slipstream", echo
   updated, Clear button enabled.
7. Tapped the app-bar theme toggle — dark mode applied immediately via
   `provider`.
8. Navigated `/list` via `navigate(...)`; scrolled the ListView with
   `perform_scroll` (down 1200 px) and tapped `list_item_19` — confirmed tap
   ripple.
9. Tried `perform_scroll_until_visible` for `list_item_30` and for
   `byText("Item #30")`; both failed (lazy-list limitation — see cons).
10. Navigated to `/form`; filled name + email, toggled subscribe, submitted —
    result card rendered correctly.
11. Hot-restarted, re-navigated to `/form`, tapped Submit with empty fields —
    validators fired correctly on both TextFormFields.
12. Opened the Drawer via `perform_semantic_action(tap, node_id=10)` (no label
    on the hamburger); tapped `drawer_about` — landed on `/about`. `get_route`
    confirmed the nested route state.
13. Closed the app with `close_app` and wrote this feedback.
