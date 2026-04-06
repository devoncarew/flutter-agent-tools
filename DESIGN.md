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

The suite is distributed as a **Claude Code plugin**, installable with a single
command. This gives:

- **Developers:** low-friction installation; no manual server setup or prompt
  engineering required.
- **Agents:** tools are automatically available via native Claude Code
  primitives (Hooks, MCP) without requiring explicit instruction.

## Tool 1: Dependency Health Hook

**Mechanism:** Claude Code `PreToolUse` hook

**Trigger points:**

- `Bash` tool calls matching `flutter pub add` or `dart pub add`
- `Write`/`Edit` tool calls targeting `pubspec.yaml`

**Behavior:**

- Queries the pub.dev API to validate each package before it is added.
- **Blocks** if a package is officially marked discontinued, and reports the
  official replacement if one is listed.
- **Warns** (without blocking) if a package appears abandoned by heuristics (see
  below).
- **Fails open** on infrastructure errors (network timeout, missing
  dependencies) — the hook should never block the agent due to its own tooling
  failures.

**Abandonment heuristics** (beyond the official `isDiscontinued` flag):

- Last publish date older than ~3 years (blunt; useful as a secondary signal
  only).
- The package's own dependencies pin to severely outdated versions of core
  ecosystem packages (e.g., a very old `package:meta`). This is a stronger
  signal and worth implementing in a future iteration.
- README or repository signals (fork status, archived repo). Lower priority;
  requires additional API calls.

**Implementation:** Shell script (`dep_health_check.sh`) receiving JSON on stdin
from Claude Code. Requires `curl` and `jq`.

**Current state:** Functional for the `flutter pub add` path. The `pubspec.yaml`
Write/Edit guard is a stub — it requires diffing the incoming file content to
isolate newly added packages, which is more complex.

## Tool 2: Package API Inspector

**Mechanism:** MCP server command

**Motivation:** Agents reading raw `.pub-cache` source to discover a package API
is highly token-inefficient. They read implementation files, private members,
and method bodies — none of which are needed.

A more subtle failure mode also occurs: agents frequently rely on their own
training-data summaries of a package's API, which are often subtly wrong
(incorrect parameter names, missing required vs. optional distinctions, wrong
constructor shapes). This causes first-attempt code to fail, triggering a
correction loop that consumes more tokens than reading the source would have. A
reliable, accurate API dump eliminates this loop entirely.

**Observed agent behaviour during development of this plugin:** During
development we needed the APIs for `dart_mcp`, `flutter_daemon`, and
`unique_names_generator`. In each case the pattern was:

1. Agent fetched pub.dev or produced a training-data summary — approximately
   right but with meaningful errors (wrong `registerTool` signature, wrong
   `log()` signature, missing name clash with `dart:developer`).
2. We had to go back to the pub cache to read actual source and fix the errors.

A Package API Inspector that returns accurate signatures up front would have
eliminated step 2 in every case.

**Output format: simplified Dart stubs**

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

**Interaction model: agent-directed, progressive detail**

Rather than returning a single large dump, the tool accepts a `kind` parameter
so the agent requests only what it needs at each step:

| `kind`            | Returns                                                                                                                                                                                                                |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `package_summary` | Version, entry-point import, one-paragraph README orientation, list of public libraries and top-level exported names. Enough to orient and decide what to look at next.                                                |
| `library_stub`    | Full public API for one library as a Dart stub file: all exported classes, mixins, extensions, top-level functions and constants, with signatures but no bodies. Mixin-contributed methods are inlined and attributed. |
| `class_stub`      | Stub for a single named class/mixin/extension, including inherited and mixin-contributed members. Useful when the agent knows exactly what it needs.                                                                   |
| `example`         | Contents of a specific example file from `example/` or inline `/// ```dart` samples extracted from a class or library.                                                                                                 |

The typical call sequence for an unfamiliar package:

1. `package_summary` — orient, identify the relevant library.
2. `library_stub` — get all signatures for that library.
3. `class_stub` or `example` — drill into a specific class or usage pattern if
   signatures alone aren't enough.

**Inputs:**

- `package`: package name (required).
- `kind`: one of the values above (required).
- `library` / `class`: target for `library_stub`, `class_stub`, `example`
  (required for those kinds).
- `version`: defaults to the version resolved in `pubspec.lock`; override
  allowed for packages not yet in the lockfile.

**Source:** `.pub-cache` only — already downloaded, always matches the resolved
version, no network required.

**What the inspector does NOT cover:**

- String constants used as protocol/event identifiers (e.g. `'app.started'` in
  the Flutter daemon protocol). These live in implementation code, not the
  public API surface.
- Runtime behaviour, error conditions, or semantic nuance not captured in
  signatures or doc comments.

**Design reference:** Modeled on the architecture of the
[`jot`](https://github.com/devoncarew/jot) tool.

**Implementation notes:**

- **AST-based** (via `package:analyzer`) is preferred over dartdoc JSON. Dartdoc
  requires a prior analysis pass and may not be present; the analyzer element
  model is always derivable from source and correctly resolves mixin
  contributions.
- **Version resolution**: read from `pubspec.lock` in the current working
  directory.
- **Caching**: the pub cache directory is already versioned
  (`{package}-{version}/`), so source is stable. Parse-result caching is a
  nice-to-have for large packages like `package:analyzer` itself.

## Tool 3: Flutter UI Agent

**Mechanism:** MCP server commands

**Motivation:** A Playwright analogue for Flutter. Enables agents to observe and
interact with a running Flutter app for layout debugging, state verification,
and end-to-end workflow validation.

**Behavior:**

_Launch and device selection:_

- Automatically builds and launches the Flutter app without manual setup from
  the developer.
- Returns a session ID used by subsequent commands.
- **Device auto-selection:** When `device_id` is omitted, the server runs
  `flutter devices --machine` and picks the best available device using the
  preference order below. The goal is zero-configuration launch on any
  workstation.

  **Preference order:**

  1. **Desktop matching host OS** (macOS / windows / linux) — always available
     on the host platform, fast to build (no Xcode/Gradle overhead), supports
     hot reload + inspector + screenshots. Best default for agent use.
  2. **iOS Simulator** (if already running, macOS only) — better mobile
     fidelity but requires Xcode; the server discovers a booted simulator but
     never launches one (takes 30+ seconds, and the agent can't know if the
     user wants it).
  3. **Android emulator** (if already running) — same rationale as iOS.
  4. **Connected physical device** — least predictable, but usable.
  5. **Web (Chrome)** — deprioritized; web doesn't support
     `ext.flutter.inspector.screenshot` or VM service `evaluate` the same way.

  **Platform-support check:** Before selecting a device, the server verifies
  the project has the corresponding platform folder (e.g. `macos/` for
  desktop-macOS). A missing folder means `flutter run -d macos` would fail,
  so that device is skipped.

  **Actionable errors:** If no usable device is found, the error includes the
  full device list and a concrete suggestion (e.g. "Run
  `flutter create --platforms=macos .` to enable desktop, or start an iOS
  simulator.").

  **Explicit override:** When `device_id` is provided, auto-selection is
  bypassed entirely — the value is passed through to `flutter run --device-id`.

  **Why not a separate `flutter_list_devices` tool?** Auto-selection handles
  the happy path, and the error path handles discovery. A separate list command
  adds a step agents would need to learn to call first — more friction, not
  less. If a need emerges later, it can be added without changing the launch
  flow.

_Introspection and interaction (via Dart VM Service):_

- Query semantic/interactive elements (rather than dumping the full widget tree,
  which is token-heavy).
- Tap an element by semantics label.
- Inject text into a field.
- Scroll to bring off-screen elements into view.
- Pull unhandled exceptions from the runtime.

**Design reference:**

- [Playwright MCP](https://playwright.dev/docs/getting-started-mcp) — overall
  model.
- [flight_check issue #17](https://github.com/devoncarew/flight_check/issues/17)
  — use cases and requirements.

**Resolved questions:**

- Launch abstraction: `flutter run --machine` with VM service attachment is the
  right approach. It works on all device types without a test harness.
- Screenshot: feasible on all device types via
  `ext.flutter.inspector.screenshot` with physical window dimensions from
  `evaluate`.

### `flutter_evaluate_expression`

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

### Planned: `flutter_query_ui`

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

**`route` mode — capabilities and limitations:**

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
- **No route path.** The output contains widget class names, not route strings
  (e.g. `/podcast/:id`). An agent that needs to call `context.go(...)` still
  has to read the routes file to find the correct path and its parameters.
  go_router has no VM service extensions that expose the current URI, and
  `ModalRoute.of(context)` requires a `BuildContext` that cannot be reached
  cheaply via `evaluate`.
- **Summary tree depth.** The widget tree is fetched with `isSummaryTree: true`,
  which omits internal Flutter widgets. If a project wraps all screens in a
  private class, those wrappers may be the first locally-created widget found,
  hiding the real screen name.
- **Multiple navigators.** Nested navigator setups (shell routes, dialog
  overlays, bottom-sheet navigators) each appear as a separate stack. The tool
  suppresses navigators composed entirely of private widgets but cannot
  automatically determine which navigator is "primary" in all cases.

**Open questions:**

- The semantics tree is disabled by default to save resources. We need to
  evaluate whether the one-time enable call has observable performance impact on
  typical development-mode apps.
- App state and authentication: navigating apps that require login or seeded
  data before reaching the UI under test is unsolved.

## MCP Server Architecture

Both Tool 2 and Tool 3 are exposed through a single Dart MCP server. Using Dart
is the natural fit given the domain and avoids introducing a Node.js runtime
dependency.

**Tool surface (✓ = implemented, [planned] = not yet):**

```
// Tool 2
package_info(package, kind, library?, class?, version?) → String  [planned]

// Tool 3 — session lifecycle
✓ flutter_launch_app(working_directory, target?, device?) → session_id
✓ flutter_perform_reload(session_id, full_restart?) → void
✓ flutter_close_app(session_id) → void

// Tool 3 — inspection (high value)
✓ flutter_take_screenshot(session_id, pixel_ratio?) → PNG
✓ flutter.error log events  // push; includes widget IDs for flutter_inspect_layout
✓ flutter_inspect_layout(session_id, widget_id?) → String  // widget_id=null → root
✓ flutter_evaluate_expression(session_id, expression) → String  // arbitrary Dart on main isolate
✓ flutter_query_ui(session_id, mode) → String  // route: ✓ | semantics: [planned] | widget_tree: [planned]

// Tool 3 — app interaction (useful but lower priority for coding agents)
[planned] flutter_tap(session_id, semantics_label) → void
[planned] flutter_inject_text(session_id, semantics_label, text) → void
[planned] flutter_scroll_to(session_id, semantics_label) → void
```

**Declared in `plugin.json`:**

```json
"mcpServers": {
  "flutter-agent": {
    "command": "dart",
    "args": ["run", "flutter_agent_tools:mcp_server"]
  }
}
```

## Deferred / Open Questions

- **App state and authentication (Tool 3):** Navigating apps that require login
  or specific seeded data before reaching the UI under test is unsolved. A
  future design may define an `.agent_state.md` convention for specifying
  startup states, mock data, or auth bypasses.
- **pubspec.yaml guard (Tool 1):** The Write/Edit hook path requires diffing
  file content to extract newly added packages. Needs a dedicated design pass.
- **Abandonment heuristics (Tool 1):** The dependency-graph signal (checking a
  package's own deps for staleness) is more reliable than publish date and
  should replace it as the primary heuristic.
- **Plugin marketplace publication:** Distribution mechanism beyond
  `--plugin-dir` local testing is not yet planned.

## References

- [flight_check issue #17](https://github.com/devoncarew/flight_check/issues/17)
  — Flutter UI agent use cases
- [flight_check issue #2](https://github.com/devoncarew/flight_check/issues/2) —
  pub outdated hook generalization
- [Playwright MCP](https://playwright.dev/docs/getting-started-mcp)
- [Playwright MCP (Simon Willison walkthrough)](https://til.simonwillison.net/claude-code/playwright-mcp-claude-code)
