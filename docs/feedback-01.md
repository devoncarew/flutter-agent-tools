# MCP Server Feedback — Session 01 (2026-04-07)

Session context: accessibility improvements to a Flutter podcast app
(Podtastic), adding semantic labels across multiple screens, navigating the app
via the MCP tools, installing and integrating `share_plus`.

---

## flutter-inspect

### Tools used

`flutter_launch_app`, `flutter_reload`, `flutter_take_screenshot`,
`flutter_get_semantics`, `flutter_get_route`, `flutter_navigate`, `flutter_tap`,
`flutter_evaluate`, `flutter_inject_text`

### What went well

- **`flutter_launch_app` / `flutter_reload`** — fast and reliable throughout
- **`flutter_get_semantics`** — the most-used tool; the flat list format with
  id/role/label/size/actions was easy to act on; the accessibility work would
  have been very hard without it
- **`flutter_take_screenshot`** — reliable visual confirmation after reloads
- **`flutter_get_route`** — go_router path enrichment was a nice touch; very
  useful for confirming navigation
- **`flutter_navigate`** — worked perfectly for simple paths
- **`flutter_evaluate` with `library_uri`** — powerful escape hatch once the
  right library scope was identified

### Bugs / things that didn't work

**1. `flutter_tap` / `flutter_inject_text` wrong `library_uri`** [done]

Both tools fail because `SemanticsActionEvent` is not in scope in the library
they evaluate against. The fix is to use
`package:flutter/src/rendering/binding.dart` (which imports
`package:flutter/semantics.dart` and gets both `SemanticsAction` and
`SemanticsActionEvent` without a prefix) instead of
`package:flutter/src/semantics/semantics.dart`.

Workaround used: call `flutter_evaluate` directly with the correct
`library_uri`.

**2. Generics mangled in `flutter_evaluate` expressions**

`<Type>` in expressions gets HTML-entity-encoded (`&lt;Type&gt;`) before the
expression reaches the Dart compiler, breaking any generic method call (e.g.
`Provider.of<SearchProvider>(...)`, `context.read<AppStorage>()`). A
pre-processing unescape step on the expression string would fix this.

**3. `flutter_inject_text` doesn't fire `onChanged`**

`SemanticsAction.setText` updates a text field's internal state but bypasses
`TextField.onChanged`. Search and filter UIs driven by `onChanged` won't
respond. Consider following up `setText` with a submit or editingComplete
action, or at minimum document the limitation prominently in the tool
description.

**4. `flutter_navigate` can't pass `extra` args**

go_router routes that require `state.extra` (typed objects passed alongside the
path) are unreachable via `flutter_navigate`. A `flutter_push` variant that
accepts a JSON `extra` payload would cover these cases.

**5. Semantics node IDs change after hot reload** [done]

IDs must be re-fetched after every reload. Worth noting in the `flutter_reload`
response that previously observed node IDs are invalidated, or documenting this
clearly in `flutter_get_semantics` output.

### Suggested additions (priority order)

1. Fix the bugs above first — especially the `library_uri` issue, which made
   `flutter_tap` and `flutter_inject_text` completely unusable
2. **`flutter_widget_tree`** with filtering / subtree queries — would help
   diagnose why certain nodes don't appear in the semantics tree (off-screen?
   inside `ExcludeSemantics`? merged?) without having to read source files
3. **`flutter_scroll_to`** — useful but lower priority until the tap tools work
   reliably

### Native system UI note [done]

On macOS desktop, `flutter_take_screenshot` only captures the Flutter view.
Native system panels (`NSSharingServicePicker`, system share sheets, etc.) are
not captured. This is expected but worth documenting so agents don't assume a
feature isn't working just because the screenshot looks unchanged.

---

## dart-api

### Tools used

`package_info` with kinds: `package_summary`, `class_stub`

### What went well

- The `package_summary` → `class_stub` workflow was natural and fast
- API signatures were accurate and matched the installed package version
  exactly, which is the core value of this tool over training-data recall
- The error message when a package isn't in the pub cache ("Add it to
  pubspec.yaml and run `dart pub get`") is clear and actionable

### Discoverability issue: `library_stub` [done]

The `library_stub` kind exists but is easy to miss. When fetching a package
summary, the natural next step is to fetch individual class stubs — which works
but is slower than fetching the entire library at once. The `package_summary`
response lists exported class names but doesn't hint that `library_stub` can
retrieve all of them in one call.

**Suggested fix:** append a note to the `package_summary` output along the lines
of: _"Use `library_stub` to retrieve full signatures for all exported names in
one call, or `class_stub` to target a single class."_

## General issues

### hooks crashes [done]

There were many, many, many "PreToolUse:Bash hook error" errors in the console;
I didn't dig into the logs, but I assume they were due to one of our hooks.

### long names are long

Our plugin, MCP server, and tool names do matter; here's what a user seems:

```
plugin:flutter-agent-tools:flutter-inspect - flutter_close_app (MCP)(session_id: "hostile_puma_1675")
```

We may want to shorten one or more of the names.

I'd also like to switch to some more curated words for the session names. Short
words, playful, and a shorter numeric suffix?

flutter-inspect:

'flutter-inspect' => 'inspector'? We strip the leading flutter\_ prefix from the
tools?

'session_id => 'session'?

```
plugin:flutter-agent-tools:flutter-inspect - flutter_close_app (MCP)(session_id: "hostile_puma_1675")

=>

plugin:flutter-agent-tools:inspector - close_app (MCP)(session: "sunny_fox_42")
```

dart-api:

'dart-api' => 'packages'? 'package_info' => 'api'?

So the call then looks like:

```
plugin:flutter-agent-tools:packages - api (MCP) ( ... )
```

- [x] dart-api => packages
- [x] package_info => api

- [x] flutter-inspect => inspector
- [x] flutter_launch_app -> run_app
- [x] flutter_close_app -> close_app
- [x] flutter_inject_text => set_text? perform_set_text?
- [x] flutter_tap => tap? perform_tap?
- [ ] make session_id optional? There's generally only ever going to be one
      session
- [ ] when starting a session, send back a short how-to guide?

- [x] .github/workflows/ci.yml
- [x] .claude-plugin/plugin.json
- [x] bin/
- [x] scripts/

- plugin:flutter-toolkit:inspector (for runtime state and interaction)
- plugin:flutter-toolkit:packages (for API summarization)

- [x] rename dart api server to packages
- [x] rename screenshot to take_screenshot
- rename plugin to flutter-toolkit
- split packages:api command into package_summary, library_stub, and class_stub
