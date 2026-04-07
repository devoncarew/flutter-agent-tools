# Design: Flutter Agent Tools

## Problem Statement

AI coding agents working on Dart and Flutter projects face two structural
failure modes:

1. **Training cutoff drift.** Agents hallucinate outdated or discontinued
   package APIs. When they attempt to self-correct by reading raw source from
   `.pub-cache`, they consume large amounts of context window on implementation
   details rather than public API surface.

2. **No runtime visibility.** Static analysis alone is insufficient for Flutter
   development. Agents cannot observe layout failures, verify state changes, or
   diagnose render issues without being able to "see" the running app.

## Distribution

The suite is distributed as a Claude Code plugin, installable with a single
command. This gives:

- **Developers:** low-friction installation; no manual server setup or prompt
  engineering required.
- **Agents:** tools are automatically available via native Claude Code
  primitives (Hooks, MCP) without requiring explicit instruction.

## Tool 1: Package Currency Hook

**Mechanism:** Claude Code `PreToolUse` hook

**Trigger points:**

- `Bash` tool calls matching `flutter pub add` or `dart pub add`
- `Write`/`Edit` tool calls targeting `pubspec.yaml`

**Behavior:**

All checks are warnings (exit 0) — the agent sees the message and decides
whether to proceed. The hook never hard-blocks, because the agent may have
legitimate reasons to override (e.g. a private package not on pub.dev).

- **Discontinued:** if `isDiscontinued == true` on pub.dev, warns with the
  official replacement if one is listed.
- **Old major version:** if the requested constraint targets an older major
  version than what pub.dev currently publishes (e.g. `http:^0.13.0` when latest
  is `1.x`), warns and suggests the current major.
- **Not found:** if the package name doesn't exist on pub.dev, warns — could be
  a private package or a typo.
- **Fails open:** on network errors or any other infrastructure failure, the
  hook exits cleanly without blocking.

**Unofficial blocklist:**

The two failure modes seen in practice are discontinued packages and old major
versions — both covered above. A third case exists: packages that are
effectively abandoned but not officially marked `isDiscontinued` on pub.dev
(e.g. packages that have been superseded by a community fork). A small curated
blocklist in `lib/src/deps/blocklist.dart` would cover these. Each entry should
name the package, a reason, and the recommended alternative.

**Implementation:** Dart CLI (`bin/deps_check.dart`) invoked via a thin shell
launcher (`scripts/deps_check.sh`). Reads tool input JSON from stdin; mode
selected via `--mode=pub-add` or `--mode=pubspec-guard`. The pubspec-guard mode
diffs the YAML before and after the edit to find newly added packages and runs
the same checks.

**Current state:** Both modes functional.

## Tool 2: Package API Retrieval and Summarization

MCP server name: `dart-api` | Entry point: `bin/shorthand_mcp.dart`

### Motivation

Agents working on Dart and Flutter projects need accurate package API
information, but their two natural paths to get it are both expensive:

- **Reading `.pub-cache` source directly** is token-inefficient — they read
  implementation files, private members, and method bodies, none of which are
  needed.
- **Relying on training-data summaries** produces subtly wrong results —
  incorrect parameter names, missing required vs. optional distinctions, wrong
  constructor shapes. This causes first-attempt code to fail, triggering a
  correction loop that consumes more tokens than reading the source would have.

This tool eliminates both problems by retrieving the public API surface from the
local pub cache and summarizing it into a compact, accurate form.

Observed agent behaviour during development of this plugin: we needed the APIs
for `dart_mcp`, `flutter_daemon`, and `unique_names_generator`. In each case:

1. Agent produced a training-data summary — approximately right but with
   meaningful errors (wrong `registerTool` signature, wrong `log()` signature,
   missing name clash with `dart:developer`).
2. We had to go back to the pub cache to read actual source and fix the errors.

Retrieving accurate signatures up front would have eliminated step 2 each time.

### Output format: simplified Dart stubs

Responses are Dart source files with method bodies removed and private
declarations omitted — analogous to TypeScript's `.d.ts` declaration files. This
format is preferred over Markdown because:

- The agent is writing Dart; no translation step means fewer transcription
  errors. Seeing `Future<void> restart({bool? fullRestart, String? reason})` is
  unambiguous in a way that a prose description is not.
- Dart's type system captures nullability, required vs. optional, positional vs.
  named, generic bounds, and function types exactly. Markdown approximates them.
- Import lines appear as literal Dart imports — the exact lines the agent will
  write.
- Doc comments and `/// ```dart` usage examples are co-located with their
  declarations, matching how Dart packages already document themselves.

### Interaction model: agent-directed, progressive detail

Rather than returning a single large dump, the tool accepts a `kind` parameter
so the agent requests only what it needs at each step:

| `kind`            | Returns                                                                                                                                                                                                                |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `package_summary` | Version, entry-point import, one-paragraph README orientation, list of public libraries and top-level exported names. Enough to orient and decide what to look at next.                                                |
| `library_stub`    | Full public API for one library as a Dart stub file: all exported classes, mixins, extensions, top-level functions and constants, with signatures but no bodies. Mixin-contributed methods are inlined and attributed. |
| `class_stub`      | Stub for a single named class/mixin/extension, including inherited and mixin-contributed members. Useful when the agent knows exactly what it needs.                                                                   |

The typical call sequence for an unfamiliar package:

1. `package_summary` — orient, identify the relevant library.
2. `library_stub` — get all signatures for that library.
3. `class_stub` — drill into a specific class if signatures alone aren't enough.

Inputs:

- `package`: package name (required).
- `kind`: one of the values above; defaults to `package_summary`.
- `project_directory`: path to the Dart/Flutter project (required).
- `library`: target library URI for `library_stub` and `class_stub`.
- `class`: target class/mixin/extension name for `class_stub`.

Source: `.pub-cache` only — already downloaded, always matches the resolved
version, no network required.

What this tool does NOT cover:

- String constants used as protocol/event identifiers (e.g. `'app.started'` in
  the Flutter daemon protocol). These live in implementation code, not the
  public API surface.
- Runtime behaviour, error conditions, or semantic nuance not captured in
  signatures or doc comments.

Design reference: Modeled on the architecture of the
[`jot`](https://github.com/devoncarew/jot) tool.

### Current state

All three kinds are implemented and the MCP server is registered in the plugin.

## Tool 3: Flutter UI Agent

Mechanism: MCP server commands

Motivation: A Playwright analogue for Flutter. Enables agents to observe and
interact with a running Flutter app for layout debugging, state verification,
and end-to-end workflow validation.

### Launch and device selection:

- Automatically builds and launches the Flutter app without manual setup from
  the developer.
- Returns a session ID used by subsequent commands.
- **Device auto-selection:** When `device_id` is omitted, the server runs
  `flutter devices --machine` and picks the best available device using the
  preference order below. The goal is zero-configuration launch on any
  workstation.

  Preference order:
  1. **Desktop matching host OS** (macOS / windows / linux) — always available
     on the host platform, fast to build (no Xcode/Gradle overhead), supports
     hot reload + inspector + screenshots. Best default for agent use.
  2. **iOS Simulator** (if already running, macOS only) — better mobile fidelity
     but requires Xcode; the server discovers a booted simulator but never
     launches one (takes 30+ seconds, and the agent can't know if the user wants
     it).
  3. **Android emulator** (if already running) — same rationale as iOS.
  4. **Connected physical device** — least predictable, but usable.
  5. **Web (Chrome)** — deprioritized; web doesn't support
     `ext.flutter.inspector.screenshot` or VM service `evaluate` the same way.

  **Platform-support check:** Before selecting a device, the server verifies the
  project has the corresponding platform folder (e.g. `macos/` for
  desktop-macOS). A missing folder means `flutter run -d macos` would fail, so
  that device is skipped.

  **Actionable errors:** If no usable device is found, the error includes the
  full device list and a concrete suggestion (e.g. "Run
  `flutter create --platforms=macos .` to enable desktop, or start an iOS
  simulator.").

  **Explicit override:** When `device_id` is provided, auto-selection is
  bypassed entirely — the value is passed through to `flutter run --device-id`.

  **Why not a separate `flutter_list_devices` tool?** Auto-selection handles the
  happy path, and the error path handles discovery. A separate list command adds
  a step agents would need to learn to call first — more friction, not less. If
  a need emerges later, it can be added without changing the launch flow.

### Introspection and interaction (via Dart VM Service):

- Query semantic/interactive elements (rather than dumping the full widget tree,
  which is token-heavy).
- Tap an element by semantics label.
- Inject text into a field.
- Scroll to bring off-screen elements into view.
- Pull unhandled exceptions from the runtime.

Design references:

- [Playwright MCP](https://playwright.dev/docs/getting-started-mcp) — overall
  model.
- [flight_check issue #17](https://github.com/devoncarew/flight_check/issues/17)
  — use cases and requirements.

### `flutter_evaluate`

Runs an arbitrary Dart expression on the main isolate via the VM service
`evaluate` RPC and returns the result as a string.

This covers a class of debugging questions that inspector extensions cannot
answer — specifically, binding-layer and platform-layer state that exists below
the widget tree:

- `WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio.toString()`
- `MediaQuery.of(context).toString()` — requires a valid `BuildContext`
- Any `FlutterView` property (`physicalSize`, `padding`, `viewInsets`)

The inspector tree shows widget and render-object state; `evaluate` covers
everything else. We already use this internally for `getPhysicalWindowSize()`;
exposing it as a tool gives agents direct access without requiring a dedicated
method for every possible query.

### `flutter_query_ui`

An experimental tool for agents that want a high-level description of what is
currently on screen — useful for navigating to a specific app state, confirming
a change took effect, or understanding the current route before drilling into
layout details.

Rather than committing to a single output format, the tool is parameterized by a
`mode` argument so individual modes can be added or removed independently as we
learn what's actually useful:

| `mode`        | Returns                                                                        | Source                                               |
| ------------- | ------------------------------------------------------------------------------ | ---------------------------------------------------- |
| `semantics`   | Flat list of visible, interactive nodes (labels, roles, bounding boxes)        | Semantics tree (via `evaluate` to enable + traverse) |
| `widget_tree` | Summary widget tree filtered to user-written widgets (omits Flutter internals) | `getRootWidgetTree(isSummaryTree: true)`             |
| `route`       | Navigator stack with screen widget names, source locations, current marker     | `getRootWidgetTree(isSummaryTree: true)`             |

The semantics tree is most token-efficient for "what can I interact with?"
questions — it's a flat list of user-visible nodes with labels and bounding
boxes, filtered by the Flutter framework to exclude invisible/internal nodes.
The widget tree adds structural context (nesting, widget types) at higher token
cost. Route info is low-cost and answers the most common orientation question.

A sample semantics node from a real app:

```
SemanticsNode#6
  Rect.fromLTRB(0.0, 0.0, 379.0, 80.0)
  actions: focus, tap
  flags: isButton, hasEnabledState, isEnabled, isFocusable, hasSelectedState
  label: "Betelgeuse\nRed supergiant · 700 solar radii"
  textDirection: ltr
```

The semantics tree requires calling `RendererBinding.instance.ensureSemantics()`
once to enable it; after that, nodes are maintained by the framework. The tree
will not be present on apps built in release mode.

#### `route` mode — capabilities and limitations

The `route` mode traverses the summary widget tree to find `Navigator` nodes and
resolves each stack entry to the first locally-defined screen widget (i.e. not
from `.pub-cache`). Navigators whose entire stack resolves to private-named
widgets (e.g. go_router's `_AppShell` shell-route wrapper) are suppressed.

What it is good for:

- Orientation: confirming which screen is currently on top.
- Back-stack context: understanding how the user arrived at the current screen.
- Pointing the agent at the right source file (`lib/app/routes.dart:56`) before
  it reads or edits routing code.

Limitations:

- **Route path (non-go_router apps).** For apps not using go_router, the output
  contains widget class names only, not route strings. An agent that needs to
  call `context.go(...)` still has to read the routes file to discover valid
  paths and their required parameters. go_router apps get the actual URI via
  `GoRouter.state.uri` (see enrichment section below).
- **Summary tree depth.** The widget tree is fetched with `isSummaryTree: true`,
  which omits internal Flutter widgets. If a project wraps all screens in a
  private class, those wrappers may be the first locally-created widget found,
  hiding the real screen name.
- **Multiple navigators.** Nested navigator setups (shell routes, dialog
  overlays, bottom-sheet navigators) each appear as a separate stack. The tool
  suppresses navigators composed entirely of private widgets but cannot
  automatically determine which navigator is "primary" in all cases.

Route path enrichment via go_router:

For apps using go_router, the actual current URI is extracted by locating
`InheritedGoRouter` in the widget tree and evaluating against its instance:

1. Walk the summary tree → find `InheritedGoRouter` node → read its `valueId`
   (e.g. `inspector-29`).
2. `inspectorIdToVmObjectId(valueId)` → resolve the inspector handle to a raw VM
   object ID (`objects/1234`) by evaluating
   `WidgetInspectorService.instance.toObject(id)` in the inspector library scope
   (see `FlutterServiceExtensions.inspectorIdToVmObjectId`). Note: this returns
   the `InheritedElement`, not the widget itself.
3. `evaluateOnObject(vmId, 'widget.goRouter.state.uri.toString()')` → `.widget`
   reaches the `InheritedGoRouter` widget; `.goRouter` is its field (not
   `.notifier`); `.state.uri` gives the live current path, e.g.
   `/podcast/787ae263b723`.

Detection: presence of `InheritedGoRouter` in the summary tree is sufficient to
identify a go_router app. Other popular routers (auto_route, beamer) follow the
same InheritedWidget pattern but with different field names; they can be added
as separate cases when needed.

This enrichment is best-effort: if evaluation fails (e.g. older go_router
version, or app doesn't use go_router), the route stack is still returned
without the `Current path:` line.

Programmatic navigation via go_router (planned):

Once we have the GoRouter instance via `evaluateOnObject`, we can call
navigation methods on it directly. Note the field path: the VM object is an
`InheritedElement`, so `.widget` is needed to reach the `InheritedGoRouter`,
then `.goRouter` for the `GoRouter` instance:

```dart
// Navigate to a new route:
evaluateOnObject(vmId, 'widget.goRouter.go("/podcast/123")')

// Named location (requires knowing the route name):
evaluateOnObject(vmId, 'widget.goRouter.namedLocation("podcast", pathParameters: {"id": "123"})')
```

`go()` returns void, so the handler needs to treat a null/void `InstanceRef`
result as success rather than an error. A dedicated `flutter_navigate` tool (or
a `navigate` mode on `flutter_query_ui`) would wrap this pattern: locate the
router, call `go()`, wait for a `Flutter.Navigation` event or the next
`Flutter.Frame`, then optionally re-fetch the route stack to confirm.

The agent still needs to know valid route paths and their parameters, which
means reading the app's route definition file first. This is an acceptable
prerequisite — the agent already has access to source files.

### Open questions:

- The semantics tree is disabled by default to save resources. We need to
  evaluate whether the one-time enable call has observable performance impact on
  typical development-mode apps.
- App state and authentication: navigating apps that require login or seeded
  data before reaching the UI under test is unsolved.

## MCP Server Architecture

Tools 2 and 3 are separate Dart MCP servers (`dart-api` and `flutter-inspect`).
Using Dart is the natural fit given the domain and avoids introducing a Node.js
runtime dependency. Separate servers give independent lifecycles and failure
modes — the API retrieval server is stateless; the runtime inspection server is
stateful and subprocess-heavy.

Tool surface (✓ = implemented, [planned] = not yet):

```
// dart-api server (Tool 2)
package_info(package, kind, library?, class?, version?) → String [planned]

// flutter-inspect server (Tool 3) — session lifecycle
✓ flutter_launch_app(working_directory, target?, device?) → session_id
✓ flutter_reload(session_id, full_restart?) → void
✓ flutter_close_app(session_id) → void

// flutter-inspect server (Tool 3) — inspection (high value)
✓ flutter_take_screenshot(session_id, pixel_ratio?) → PNG
✓ flutter.error log events  // push; includes widget IDs for flutter_inspect_layout
✓ flutter_inspect_layout(session_id, widget_id?) → String  // widget_id=null → root
✓ flutter_evaluate(session_id, expression) → String  // arbitrary Dart on main isolate
✓ flutter_query_ui(session_id, mode) → String  // route: ✓ (incl. go_router path enrichment) | semantics: [planned] | widget_tree: [planned]

// flutter-inspect server (Tool 3) — app interaction (useful but lower priority for coding agents)
[planned] flutter_navigate(session_id, path) → void  // go_router: via InheritedGoRouter + evaluateOnObject
[planned] flutter_tap(session_id, semantics_label) → void
[planned] flutter_inject_text(session_id, semantics_label, text) → void
[planned] flutter_scroll_to(session_id, semantics_label) → void
```

## Deferred / Open Questions

- App state and authentication (Tool 3): Navigating apps that require login or
  specific seeded data before reaching the UI under test is unsolved. A future
  design may define an `.agent_state.md` convention for specifying startup
  states, mock data, or auth bypasses.
- pubspec.yaml guard (Tool 1): The Write/Edit hook path requires diffing file
  content to extract newly added packages. Needs a dedicated design pass.
- Abandonment heuristics (Tool 1): The dependency-graph signal (checking a
  package's own deps for staleness) is more reliable than publish date and
  should replace it as the primary heuristic.
- Plugin marketplace publication: Distribution mechanism beyond `--plugin-dir`
  local testing is not yet planned.

## References

- [flight_check issue #17](https://github.com/devoncarew/flight_check/issues/17)
  — Flutter UI agent use cases
- [flight_check issue #2](https://github.com/devoncarew/flight_check/issues/2) —
  pub outdated hook generalization
- [Playwright MCP](https://playwright.dev/docs/getting-started-mcp)
- [Playwright MCP (Simon Willison walkthrough)](https://til.simonwillison.net/claude-code/playwright-mcp-claude-code)
