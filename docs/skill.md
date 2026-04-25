---
name: flutter-slipstream
description: >-
  Practical guidance for AI agents using the flutter-slipstream plugin. This
  captures things that are non-obvious from individual tool descriptions alone —
  gotchas, preferred workflows, and when to choose one tool over another.
---

# flutter-slipstream Skill

> [!NOTE] This is a draft of a **user-facing skill** — guidance for agents that
> have the plugin installed and are using its tools. It is distinct from the
> developer skill at `.claude/skills/mcp-tools/SKILL.md`, which is a reference
> for agents working on this codebase. We have not yet shipped this user-facing
> skill; maintain it as we discover useful patterns.

Practical guidance for AI agents using the flutter-slipstream plugin. This
document captures things that are non-obvious from individual tool descriptions
alone — gotchas, preferred workflows, and when to choose one tool over another.

## Recommended workflow

```
run_app → get_output → take_screenshot
  → edit source → reload → get_output → take_screenshot → repeat
```

- Always call `get_output` after `run_app`, after `reload`, and after any
  interaction tool. It drains the buffer — if you don't call it, output
  accumulates silently.
- Always `take_screenshot` after a reload to confirm the change looked right.
  Don't assume a visual edit worked.
- When `get_output` returns a `[flutter.error]` line, the widget ID in the
  summary can be passed directly to `inspect_layout` to drill into the failing
  subtree.

## Orienting on an unfamiliar app

1. `take_screenshot` — see what's on screen.
2. `get_route` — see the navigator stack, current screen widget names, and
   source file locations. Use this before editing to confirm which screen is
   active.
3. `get_semantics` — see the interactive elements. Node IDs from this output can
   be passed to `perform_semantic_action`.

## Interacting with the app

Prefer finder-based tools when `slipstream_agent` is installed:

- `perform_tap(byKey: ...)` / `perform_set_text(byKey: ...)` — the most
  reliable; add `ValueKey('my_key')` to the widget as you write it.
- `perform_tap(byText: ...)` — good for labels and button text.
- `perform_tap(byType: ...)` — useful for unique widget types.

Fall back to `perform_semantic_action` (no companion required) when the target
widget has no key and no distinctive text — e.g. a built-in `IconButton`.

### `get_semantics` after navigation

`get_semantics` can return stale data if called immediately after `navigate` or
a tap that triggers a route transition. Call `take_screenshot` first to
synchronise on a rendered frame, then call `get_semantics`.

### Tooltip text is not a semantics label

Flutter's built-in widgets sometimes set a `Tooltip` (e.g. the Drawer hamburger
button gets "Open navigation menu") but that tooltip string does **not** appear
as a semantics label in `get_semantics` output. If `get_semantics` shows a
button with no label, use its numeric node ID with `perform_semantic_action`.

### `perform_scroll_until_visible` and lazy lists

`perform_scroll_until_visible` evaluates the finder against the currently-built
widget tree. On a `ListView.builder` / `ListView.separated` with many items, the
target widget may not exist in the tree yet. Workaround: use `perform_scroll`
with a pixel offset to bring the region into view first, then use a finder-based
tool on the now-visible item.

## Learning a package API

Use the `packages` server before writing code that uses an unfamiliar package:

1. `package_summary` — entry-point import, exported name groups, README excerpt.
   Start here to orient.
2. `library_stub` — full public API as Dart signatures (no bodies). Use when you
   need to know exact parameter names or method shapes.
3. `class_stub` — single class or mixin. Use for deep dives once
   `package_summary` has identified the class of interest.

This is faster and more accurate than reading source files or relying on
training-data memory, especially for packages that have changed major versions.

## Debugging layout problems

- `inspect_layout` with no `widget_id` starts from the root.
- Widget IDs from `[flutter.error]` output can be passed directly to
  `inspect_layout` — no tree traversal needed.
- Increase `subtree_depth` when the relevant render object is several levels
  below the error widget.
- `evaluate` is useful for exact runtime values (`MediaQuery.of(...)`,
  controller state, etc.) that don't appear in the layout tree.

## Hot reload vs. hot restart

`reload` (hot reload) preserves app state and is fast, but it cannot apply
structural changes — new routes, modified `initState`, changed widget keys, or
constructor signature changes. If the app looks wrong after a reload, try
`reload` with `full_restart: true`. Expect state to reset.

## When `run_app` fails

If `run_app` returns an error with no useful details, run `flutter analyze` in
the project directory before re-launching — compile errors do not currently
surface in the `run_app` error message.
