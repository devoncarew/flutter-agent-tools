# MCP Server Feedback — Session 02 (2026-04-08)

Session context: building a new Flutter planets/solar system app from scratch —
adding dependencies (`go_router`, `google_fonts`, `provider`, `flight_check`),
downloading assets from GitHub, building a home list screen and detail screen,
checking semantics, and previewing the app in a phone form factor via
`flight_check`.

---

## plugin:flutter-slipstream:inspector

### Tools used

`run_app`, `take_screenshot`, `reload` (hot reload + full restart),
`get_semantics`, `evaluate`, `get_route`, `tap`, `inspect_layout`, `navigate`

### Tools not used

`close_app` (used at end of session), `set_text` (no text input fields in this
app)

### What went well

- **`run_app` / `reload` / `take_screenshot`** — the core loop of edit → reload
  → screenshot worked smoothly throughout; `take_screenshot` was the most-used
  tool and never let us down
- **`flight_check` integration** — `run_app` picked up the phone device preview
  automatically; no special configuration needed beyond calling
  `FlightCheck.configure()`; the session ID and workflow were unchanged
- **`navigate`** — worked perfectly for go_router paths; a clear improvement
  over having to tap through the UI; very useful when semantics weren't yet live
- **`get_route`** — go_router path + widget name is exactly the right level of
  detail; confirmed which screen was active quickly
- **`evaluate` with `library_uri`** — essential for the semantics debugging;
  being able to call `SemanticsBinding.instance.ensureSemantics()` and
  `WidgetsBinding.instance.scheduleFrame()` to bootstrap the semantics tree was
  a great escape hatch

### Bugs / things that didn't work

**1. `get_semantics` requires manual semantics bootstrap** [done]

`get_semantics` returns empty (`No visible text or interactive elements found`)
unless the caller first:

1. Calls `SemanticsBinding.instance.ensureSemantics()` via `evaluate`
2. Calls `WidgetsBinding.instance.scheduleFrame()` via `evaluate`
3. Then calls `get_semantics`

Flutter lazily enables semantics only when an accessibility service is
listening, and even after enabling it the tree isn't built until a frame is
scheduled. This two-step setup is non-obvious and had to be discovered through
debugging.

**Suggested fix:** have `get_semantics` internally call `ensureSemantics()` and
`scheduleFrame()` (with a short wait) before querying, so it just works out of
the box.

**2. `get_semantics` is blind to secondary PipelineOwner views (flight_check)**

When `flight_check` is active, the app renders inside a secondary
`PreviewFlutterView` with its own `PipelineOwner`, completely separate from the
root. `get_semantics` (and `ensureSemantics()` on the root pipeline owner) only
sees the root tree — the preview subtree is invisible to it entirely.

This means semantics inspection is broken whenever `flight_check` is in use,
even after the bootstrap workaround above.

**Suggested fix:** `get_semantics` should enumerate all active `PipelineOwner`
instances / Flutter views, not just the root one. Alternatively, `flight_check`
could be modified to forward semantics from the secondary view to the root.

**3. `tap` `node_id` type error** [done]

`tap` with `node_id: 5` (an integer) failed with:

```
Value `5` is not of type `int` at path #root["node_id"]
```

Had to fall back to using `label` instead. The `node_id` parameter appears to
have a type mismatch in the tool schema or server-side handling.

**4. `tap` with `excludeSemantics: true` doesn't navigate** [done]

After adding `excludeSemantics: true` to the `Semantics` wrapper on planet
cards, tapping via semantics node ID no longer triggered navigation. Root cause:
the `GestureDetector`'s tap action was excluded, and the outer `Semantics`
widget had no `action:tap` of its own. Workaround was to add `onTap` to the
`Semantics` widget itself. Worth documenting that `tap` relies on the
`action:tap` being present in the semantics node.

**5. `inspect_layout` `subtree_depth` type error** [done]

First call to `inspect_layout` with `subtree_depth: 3` failed with:

```
Value `3` is not of type `int` at path #root["subtree_depth"]
```

Same pattern as the `node_id` issue above — likely the same underlying schema
problem.

### Suggested additions / improvements

1. **Auto-bootstrap semantics in `get_semantics`** — the `ensureSemantics()` +
   `scheduleFrame()` dance should be internal; no caller should need to know
   about it
2. **Multi-view support in `get_semantics`** — enumerate all active views /
   pipeline owners so flight_check (and any other multi-view setup) works
3. **Fix `node_id` / `subtree_depth` type handling** — integer params are being
   rejected; check the JSON schema and server-side parsing for these fields

---

## plugin:flutter-slipstream:packages

### Tools used

`package_summary`, `class_stub`

### Tools not used

`library_stub` — `class_stub` was sufficient since `flight_check` only exports
one class (`FlightCheck`)

### What went well

- **`package_summary` → `class_stub` workflow** — clean and fast;
  `package_summary` gave enough orientation (one exported class, one library) to
  know `class_stub` was the right next call
- **Accuracy** — the `FlightCheck.configure()` signature matched exactly; no
  surprises at runtime
- **Local pub cache** — no network required; results were instant

### Minor notes

- `library_stub` wasn't needed here, but the `package_summary` output does now
  hint at it (per feedback-01 suggestion) — good improvement
- For a package with a single exported class, `package_summary` alone almost
  contains enough information; the README excerpt mentioning "call `configure`
  before `runApp`" was sufficient context to write the integration without even
  needing `class_stub`

---

## General notes

### Session ID format

Session IDs like `glad_colt_28` are a clear improvement over the previous format
— short, readable, easy to copy/paste. The two-word + number format works well.

### `flight_check` + slipstream interaction overall

The phone preview itself worked great visually — the device frame, the device
picker dropdown, the automatic activation on desktop. The only gap is the
semantics story above. Once `get_semantics` supports secondary views, the
combination of `flight_check` + slipstream will be a compelling workflow for
checking both visual and accessibility correctness at phone form factors.
