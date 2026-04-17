# Slipstream Companion Package: Design Document

## Overview

`slipstream_agent` is an optional, opt-in `dependency` that developers (or their
AI agents) can install into a Flutter app under development. It upgrades the
connection between the Slipstream MCP server and the running app from external
observation to internal cooperation — providing typed service extensions, direct
element targeting, visual feedback, and richer framework hooks.

## Philosophical Context

The original premise of Slipstream was strict non-modification: the tool should
work without touching the user's app. In practice, this premise breaks down.
Agents using the current baseline tools regularly make source changes to improve
interactability:

- Adding `Semantics` widgets with explicit labels so `tap` and `set_text` can
  find elements that lack them.
- Adding `Key` annotations to aid layout debugging.
- Wrapping entry points to inject state or bypass auth screens for testing.

These changes are necessary, ad-hoc, and scattered. The companion package
formalizes this pattern: instead of agents adding boilerplate one widget at a
time, the developer installs a single package that provides all the
instrumentation hooks Slipstream needs. The scope of app modification is bounded
and explicit.

This does not relax the zero-configuration baseline. `slipstream` MUST remain
fully functional without this package. The companion unlocks _enhanced_
capabilities and reliability — it is never strictly required.

## Core Principles

1. **Zero-Config Baseline:** All existing tools (`tap`, `set_text`, `navigate`,
   `get_semantics`, etc.) continue working without modification.
2. **Explicit Opt-In:** The MCP server must never add this package to
   `pubspec.yaml` without explicit developer consent. If an agent determines it
   would help, it must explain the benefit and ask first.
3. **Development Only:** The package uses `dart:developer` and debug APIs. All
   registration must be guarded by `kDebugMode` and aggressively tree-shaken
   from release builds.
4. **Graceful Degradation:** The MCP server detects presence via
   `ext.slipstream.ping`. If the ping fails, all tools fall back to the existing
   VM service / evaluate approach silently.

## Motivations and Features

Features are ordered by expected agent impact, not implementation complexity.

---

### Feature 1: Advanced UI Finders (No More Semantic Annotations)

**The problem this solves:** The most common source change agents make today is
adding `Semantics(label: ...)` wrappers so that `tap` and `set_text` can target
elements. This is necessary because both tools depend on the Flutter semantics
tree, which only knows about elements that have explicit semantic labels or
accessibility roles. Widgets targeted by their visual appearance or code
structure — an `ElevatedButton` with a `Key`, a `TextField` inside a specific
`Card` — are invisible to the current tools unless annotated.

**Feature:** The package exposes `flutter_test`-style finders at runtime via a
service extension:

```
ext.slipstream.interact({
  "action": "tap",
  "finder": "byKey",
  "value": "login_button"
})
```

Supported finder types:

- `byKey` — matches by `ValueKey` string. Keys are already common in production
  Flutter code for state management and testing.
- `byType` — matches by widget type name (`"ElevatedButton"`).
- `byText` — matches by visible text content (more reliable than the
  semantics-label substring match in the current `tap`/`set_text`).
- `bySemanticsLabel` — same as current semantics matching, as a fallback.

**Mechanism:** The package traverses the `Element` tree, resolves the matching
`RenderBox` geometry, and synthesizes pointer events at the correct screen
coordinates. No semantics tree required.

**Impact:** Eliminates the primary reason agents add `Semantics` annotations to
app code. Agents can target any widget the developer has already keyed — which
is common in well-structured Flutter apps.

---

### Feature 2: Scroll Support

**The problem this solves:** Scroll is currently a planned but unimplemented gap
in the baseline. Agents cannot bring off-screen content into view, which limits
interaction to whatever is visible in the first rendered frame. They currently
work around this by evaluating scroll controller expressions — fragile, requires
knowledge of the widget tree structure, and breaks across app versions.

**Feature:** The package exposes a typed scroll extension:

```
ext.slipstream.scroll({
  "direction": "down",
  "pixels": 300,
  "finder": "byType",
  "value": "ListView"
})
```

Or scroll until a finder becomes visible:

```
ext.slipstream.scroll_until_visible({
  "target": {"finder": "byKey", "value": "item_42"},
  "scrollable": {"finder": "byType", "value": "ListView"}
})
```

**Mechanism:** Resolves the target `Scrollable` via the element tree and drives
it programmatically via `ScrollController` or pointer event simulation.

---

### Feature 3: Unified Routing Adapter

**The problem this solves:** The current `navigate` tool is go_router-only. It
detects the router by locating `InheritedGoRouter` in the widget tree and
calling `widget.goRouter.go(path)` via `evaluate`. Apps using `auto_route`,
`beamer`, vanilla `Navigator 2.0`, or custom routing solutions get no
programmatic navigation support.

**Feature:** The package initialization accepts a router adapter:

```dart
SlipstreamAgent.init(
  router: GoRouterAdapter(appRouter),
  // or: router: AutoRouterAdapter(appRouter),
  // or: router: BeamerAdapter(routerDelegate),
);
```

The adapter exposes a uniform interface that the MCP server calls via a service
extension — `ext.slipstream.navigate({ "path": "/podcast/123" })` — without
needing to know which router is in use.

**Impact:** `navigate` and `get_route` work for any routing library. The
go_router-specific VM evaluate path becomes a fallback for apps that haven't
installed the companion package.

---

### Feature 4: Robust Service Extensions (Replace Fragile Evaluate Strings)

**The problem this solves:** Several internal operations in the baseline tools
rely on `vmService.evaluate` with raw Dart strings. Known failure modes observed
in production:

- **HTML encoding of generics.** Models generating expressions like
  `Provider.of<SearchProvider>(context)` sometimes emit `&lt;SearchProvider&gt;`
  instead of `<SearchProvider>`. The Dart compiler rejects this. We work around
  it by unescaping HTML entities before evaluation, but this is fragile.
- **Library scope confusion.** Expressions referencing types not in scope at the
  evaluation target require passing the correct `library_uri` — easy to get
  wrong and produces cryptic "undefined name" errors.
- **String escaping.** Expressions containing quotes or special characters must
  be carefully escaped before being embedded in JSON. One formatting mistake
  silently evaluates the wrong thing.

**Feature:** The package registers strongly-typed JSON RPC endpoints via
`dart:developer`'s `registerExtension`:

| Extension                            | Replaces                                                   |
| ------------------------------------ | ---------------------------------------------------------- |
| `ext.slipstream.tap`                 | semantics-based `performSemanticsAction` evaluate call     |
| `ext.slipstream.set_text`            | semantics-based `setText` evaluate call                    |
| `ext.slipstream.get_semantics`       | existing semantics extension (typed wrapper)               |
| `ext.slipstream.get_layout`          | inspector `getDetailsSubtree` (typed wrapper)              |
| `ext.slipstream.navigate`            | `GoRouter.go()` evaluate call                              |
| `ext.slipstream.bootstrap_semantics` | `RendererBinding.instance.ensureSemantics()` evaluate call |

The MCP server sends structured JSON; the package executes the Dart logic
in-process and returns clean JSON. No string embedding, no library scope issues,
no HTML encoding risk.

---

### Feature 5: Ghost Overlay (Visual Intent)

**The problem this solves:** When an agent is inspecting UI or injecting taps
via the VM service, the developer watching the screen sees nothing until a
screenshot is taken or the app state visibly changes. This makes autonomous
agent sessions opaque — the developer cannot tell what the agent is targeting or
whether it's behaving sensibly.

**Feature:** The package injects a `SlipstreamOverlay` at the root of the app.
When the MCP server calls `ext.slipstream.inspect(element_id)` or before a
`tap`, the overlay draws a highly visible bounding box around the target widget
on the actual device screen, briefly then fading out.

**Impact:** Real-time visual feedback. The developer can literally see what the
agent is "looking at" before it acts. This is especially valuable during
autonomous sessions — it builds developer trust that the agent is targeting the
right element, and makes incorrect targeting immediately obvious without waiting
for a screenshot.

**Note:** This is the feature most unique to an in-process package — it cannot
be approximated by any external VM service call.

---

### Feature 6: Structured Framework Telemetry

**The problem this solves:** The baseline currently receives `Flutter.Error`
events and `Flutter.Navigation` events. Other useful framework signals are
inaccessible or require polling via `evaluate`.

**Feature:** The package hooks into framework callbacks and broadcasts clean,
structured JSON events via `postExtensionEvent`:

- `ext.slipstream.frameTime` — wall-clock time per frame; lets agents detect
  jank before screenshotting.
- `ext.slipstream.routeChanged` — router-agnostic navigation event (complements
  Feature 3).
- `ext.slipstream.windowResized` — device/window size changes
  (`PlatformDispatcher.instance.onMetricsChanged`).
- `ext.slipstream.stateChanged` — opt-in: named state change events that the
  developer's code posts explicitly, for test synchronization.

---

## Mechanics and Integration

### Installation

Added as a dependency:

```yaml
dependencies:
  slipstream_agent: ^1.0.0
```

### Initialization

Wrapped in `kDebugMode` to prevent any production leakage:

```dart
import 'package:flutter/foundation.dart';
import 'package:slipstream_agent/slipstream_agent.dart';

void main() {
  if (kDebugMode) {
    SlipstreamAgent.init(
      enableOverlay: true,
      router: GoRouterAdapter(appRouter), // optional
    );
  }
  runApp(const MyApp());
}
```

`SlipstreamAgent.init()` registers all service extensions and inserts the
overlay widget. It is a no-op if called outside `kDebugMode`.

### Agent Workflow

1. **Session Start:** When `run_app` launches the app, the MCP server connects
   to the VM Service and calls `ext.slipstream.ping`.
2. **Baseline Mode:** If the ping fails (method not found), all tools behave as
   today — semantics tree, evaluate strings, go_router-specific navigation.
3. **Enhanced Mode:** If the ping succeeds, the server routes tool calls through
   the `ext.slipstream.*` endpoints: `tap` uses the finder-based extension,
   `navigate` uses the routing adapter, `bootstrap_semantics` uses the typed
   extension, etc. The agent uses the same tool names — the routing is
   transparent.
4. **Upgrade Prompt:** If an agent repeatedly hits baseline limitations — cannot
   find a semantic node, navigation fails for a non-go*router app, scroll is
   needed — its system prompt instructs it to ask the developer: *"I'm having
   trouble targeting this element. Installing `slipstream_agent` as a dev
   dependency would let me find it by Key instead of by semantic label. Would
   you like me to add it?"\_

### Suggested Phasing

| Phase | Features                                        | Value                              |
| ----- | ----------------------------------------------- | ---------------------------------- |
| 1     | Finders (byKey, byType, byText), Scroll         | Improved widget locatability       |
| 2     | Routing adapter, Service extensions for tap/... | Reliability + multi-router support |
| 3     | Ghost Overlay, Telemetry                        | Developer trust, debugging signals |
