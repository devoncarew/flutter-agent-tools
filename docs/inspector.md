# Flutter Runtime Inspection Guide for AI Agents

## 1. Conceptual Overview: The Three Trees

To effectively debug and interact with a Flutter app—whether running as a
desktop app or on an emulated mobile device—agents must understand that
Flutter's UI is not a single DOM. It is composed of interconnected trees:

1.  **The Widget Tree (Configuration):** This is the code the developer writes.
    Widgets are immutable, lightweight blueprints. _Agents cannot debug layout
    issues by looking solely at the Widget tree._
2.  **The Element Tree (Lifecycle & State):** Represents the actual instances of
    widgets mounted on the screen. It holds the `State` objects.
3.  **The Render Tree (Geometry & Layout):** This is the engine room. Render
    objects handle painting, sizing, constraints, and hit-testing. **When
    debugging overflows, unbounded heights, or invisible widgets, the Render
    Tree is the single source of truth.**
4.  **The Semantics Tree (Interaction & Accessibility):** Because Render objects
    do not always have human-readable identifiers, the Semantics tree is how
    tools find logical elements like "buttons" and "text fields." This tree is
    strictly required for driving UI interactions.

## 2. Accessing Runtime State: The Flutter Inspector (Read-Only)

The Dart VM Service Protocol exposes `ext.flutter.inspector` extensions. These
calls return `DiagnosticsNode` JSON objects, representing the current state of
the UI.

### Key Service Calls

- `ext.flutter.inspector.getRootWidget`: Returns the root widget node with full
  detail, including its `valueId` — the inspector object handle required by the
  screenshot extension.
- `ext.flutter.inspector.getRootWidgetTree`: Returns a configurable widget tree.
  Accepts `isSummaryTree` (omit internal widgets), `withPreviews` (thumbnails),
  and `fullDetails`.
- `ext.flutter.inspector.getDetailsSubtree(arg: String, subtreeDepth: int)`: The
  heavy lifter. Returns the exhaustive property and render-object tree for a
  specific node. Use this to get `BoxConstraints`, `Size`, and flex parameters.

### Navigating `DiagnosticsNode` Data

Inspector data is generated via Dart's `debugFillProperties`, meaning property
names are polymorphic.

**Inspector / render-tree path (`getDetailsSubtree`):**

- Dimensions appear nested under a `renderObject` property, named `"size"`,
  `"view size"`, or `"geometry"` depending on the widget type.
- Values are stringified: constraints come as
  `"BoxConstraints(w=400.0, h=800.0)"`, sizes as `"Size(411.0, 300.0)"` — must
  be parsed with regex.

**`Flutter.Error` event path:**

Error events deliver a structured DiagnosticsNode tree with explicit `type`
fields on each property. Key types and what they carry:

| Type                     | Content                                                                                    |
| ------------------------ | ------------------------------------------------------------------------------------------ |
| `ErrorSummary`           | The specific error message (`level == 'summary'`)                                          |
| `ErrorDescription`       | Prose context (e.g., "The following assertion...")                                         |
| `ErrorHint`              | Suggested fix                                                                              |
| `DiagnosticsBlock`       | Named group of child nodes (e.g., "The relevant error-causing widget was")                 |
| `DiagnosticableTreeNode` | The offending widget/render object, with sub-properties `constraints`, `size`, `direction` |
| `DiagnosticsStackTrace`  | Stack frames; first frame is the call site                                                 |

The widget ID embedded in a `DiagnosticsBlock` child description or a
`DiagnosticableTreeNode` can be passed directly to `inspect_layout` for a deeper
drill-down.

## 3. The Preferred Read Path: VM Service `evaluate`

For values that are available as live Dart expressions, prefer the VM service
`evaluate` RPC over inspector string-parsing. The RPC runs real Dart code on the
isolate and returns an exact typed value — no regex, no ambiguous field names.

**Example: Getting Exact Screen Dimensions** Rather than parsing the root
RenderView's `"view size"` string from a details subtree, evaluate this
expression on the main isolate:

```dart
WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.toString()
```

## 4. Driving UI Interactions

To interact with the app (tapping, typing, scrolling) from an MCP server, the
approach is:

1. **Enable semantics** (once, at session start) — see section 6.
2. **Query the semantics tree** via VM `evaluate` to get node IDs and labels.
3. **Dispatch actions** via `SemanticsBinding.performSemanticsAction()`.

### Dispatching actions via `performSemanticsAction`

`SemanticsBinding.performSemanticsAction` is how VoiceOver and TalkBack interact
with Flutter. It accepts a `SemanticsActionEvent` with a node's integer `id`
(from the semantics tree) and a `SemanticsAction`. No screen coordinates are
needed.

```dart
// Tap a button:
SemanticsBinding.instance.performSemanticsAction(
  SemanticsActionEvent(
    type: SemanticsAction.tap,
    nodeId: 42,
    viewId: WidgetsBinding.instance.platformDispatcher.implicitView!.viewId,
  ),
)

// Type into a text field (replaces current content):
SemanticsBinding.instance.performSemanticsAction(
  SemanticsActionEvent(
    type: SemanticsAction.setText,
    nodeId: 42,
    viewId: WidgetsBinding.instance.platformDispatcher.implicitView!.viewId,
    arguments: 'hello world',
  ),
)
```

`viewId` is the integer ID of the Flutter view. For single-window apps (the
common case) `implicitView!.viewId` is always `0`.

The semantics node `id` (see section 6) is a framework-internal integer — not an
inspector handle and not a VM service object ID — but it is exactly what
`SemanticsActionEvent.nodeId` expects. No conversion is needed.

### Approaches that do NOT work for unmodified apps

- **`ext.flutter.driver.*` extensions** — require the app to import
  `flutter_driver` and register service extensions. Unavailable here.
- **`debugDumpSemanticsTree()`** — returns ASCII-art, not structured data.
- **Injecting pointer events** (`GestureBinding.handlePointerEvent`) — works but
  requires computing accurate screen coordinates by accumulating node transforms
  from the root. The `performSemanticsAction` approach is simpler and more
  robust.

## 5. Optimizing for LLM Context Windows

Flutter apps have thousands of active nodes. Sending raw JSON dumps will
instantly blow out an agent's context window. The MCP server acts as a strict
filter.

### Strategies for Efficiency

1.  **Targeted Queries:** Never dump the whole tree. Only fetch subtrees for the
    `valueId` the agent specifically requests.
2.  **Tree Shaking the JSON:** The server strips out styling properties (colors,
    fonts, borders). A "Layout Context" response should only include: Widget
    Name, Widget ID, parent/child relationships, and Layout Data (Constraints,
    Size, Flex factor).
3.  **Regex / Path Querying:** Use pseudo-selectors in the MCP server so agents
    can query specific anomalies without full traversals (e.g.,
    `flutter_query_ui(query: "find: RenderFlex where overflow == true")`).

## 6. Semantics Tree — Data Model

Sources: `engine/src/flutter/lib/ui/semantics.dart` (flag/action enums),
`packages/flutter/lib/src/semantics/semantics.dart` (`SemanticsNode`,
`SemanticsOwner`).

### Root access

```dart
// Enable (once after app start; handle intentionally not retained):
RendererBinding.instance.ensureSemantics()

// Root node (id == 0; null if semantics not yet built):
RendererBinding.instance.pipelineOwner.semanticsOwner?.rootSemanticsNode
```

### `SemanticsNode` fields

| Field                               | Type             | Notes                                                                                                                                               |
| ----------------------------------- | ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`                                | `int`            | Framework-internal integer; root is always 0. Not an inspector handle or VM service object ID, but directly usable as `SemanticsActionEvent.nodeId` |
| `rect`                              | `Rect`           | Bounding box in **local** coordinate space                                                                                                          |
| `transform`                         | `Matrix4?`       | Local → parent transform; null means identity                                                                                                       |
| `label`                             | `String`         | Primary accessibility label                                                                                                                         |
| `value`                             | `String`         | Current value (e.g. slider position, text field content)                                                                                            |
| `hint`                              | `String`         | Short description of what happens on action                                                                                                         |
| `tooltip`                           | `String`         | Tooltip text                                                                                                                                        |
| `increasedValue` / `decreasedValue` | `String`         | Value after increase/decrease action                                                                                                                |
| `textDirection`                     | `TextDirection?` | Reading direction for text fields                                                                                                                   |
| `isInvisible`                       | `bool`           | `rect.isEmpty \|\| transform.isZero()` — skip these                                                                                                 |
| `mergeAllDescendantsIntoThisNode`   | `bool`           | When true, children are rolled up into this node                                                                                                    |
| `isMergedIntoParent`                | `bool`           | This node's data is already in its parent                                                                                                           |

**Tree walking:**

```dart
node.visitChildren((SemanticsNode child) {
  // return true to continue, false to stop
  return true;
});
```

### Coordinate system

`rect` is in the node's **local** coordinate system, not screen coordinates. The
root node's local system is screen coordinates (no parent transform). For child
nodes, accumulate `transform` values from the root to convert to screen
coordinates. Many top-level widgets (AppBar, body, FAB) are direct children of
the root, so their `rect` values are already in screen coordinates.

To compute a node's screen rect in a VM evaluate expression, chain transforms:

```dart
// Accumulate parent transforms from root down to node.
// MatrixUtils.transformPoint(transform, point) applies a Matrix4.
```

### `SemanticsFlag` bitmask values (from `dart:ui`)

Flags are set in a bitmask (`int`). The most useful for agents:

| Flag                         | Bit     | Meaning                                         |
| ---------------------------- | ------- | ----------------------------------------------- |
| `hasCheckedState`            | 1       | Node can be checked/unchecked (checkbox, radio) |
| `isChecked`                  | 2       | Currently checked                               |
| `isCheckStateMixed`          | `1<<25` | Tristate checkbox — mixed state                 |
| `hasSelectedState`           | `1<<28` | Node can be selected (tab, list item)           |
| `isSelected`                 | 4       | Currently selected                              |
| `isButton`                   | 8       | Button role                                     |
| `isTextField`                | 16      | Text input field                                |
| `isSlider`                   | `1<<23` | Slider control                                  |
| `isLink`                     | `1<<22` | Interactive hyperlink                           |
| `isImage`                    | `1<<14` | Image                                           |
| `isHeader`                   | `1<<9`  | Section header                                  |
| `isFocusable`                | `1<<21` | Can receive input focus                         |
| `isFocused`                  | `1<<5`  | Currently has input focus                       |
| `hasEnabledState`            | `1<<6`  | Node can be enabled/disabled                    |
| `isEnabled`                  | `1<<7`  | Currently enabled                               |
| `isInMutuallyExclusiveGroup` | `1<<8`  | Radio button (one of a group)                   |
| `isObscured`                 | `1<<10` | Password field                                  |
| `isMultiline`                | `1<<19` | Multi-line text field                           |
| `isReadOnly`                 | `1<<20` | Read-only text field                            |
| `hasToggledState`            | `1<<16` | Node can be toggled on/off (Switch)             |
| `isToggled`                  | `1<<17` | Currently toggled on                            |
| `hasExpandedState`           | `1<<26` | Can expand/collapse (SubmenuButton)             |
| `isExpanded`                 | `1<<27` | Currently expanded                              |
| `isHidden`                   | `1<<13` | Off-screen; skip for visible-element queries    |
| `isLiveRegion`               | `1<<15` | Updates auto-announced (SnackBar)               |
| `hasImplicitScrolling`       | `1<<18` | Container scrolls to reveal focus (ListView)    |
| `scopesRoute`                | `1<<11` | Root of a route subtree (Dialog, Drawer)        |
| `namesRoute`                 | `1<<12` | Label names the current route                   |
| `hasRequiredState`           | `1<<29` | Form field that may be required                 |
| `isRequired`                 | `1<<30` | Currently required                              |

### `SemanticsAction` bitmask values (from `dart:ui`)

Actions the node can receive. For interaction tools, the most relevant:

| Action                       | Bit               | Use                               |
| ---------------------------- | ----------------- | --------------------------------- |
| `tap`                        | 1                 | Tap the node                      |
| `longPress`                  | 2                 | Long press                        |
| `scrollLeft` / `scrollRight` | 4 / 8             | Horizontal scroll                 |
| `scrollUp` / `scrollDown`    | 16 / 32           | Vertical scroll                   |
| `increase` / `decrease`      | 64 / 128          | Slider adjustment                 |
| `setText`                    | `1<<21`           | Replace text field content        |
| `setSelection`               | `1<<11`           | Move cursor / set selection range |
| `focus`                      | `1<<22`           | Request input focus               |
| `expand` / `collapse`        | `1<<24` / `1<<25` | Expand or collapse                |
| `dismiss`                    | `1<<18`           | Dismiss (dialog, snackbar)        |
| `showOnScreen`               | `1<<8`            | Scroll to make this node visible  |

### Filtering for visible interactive nodes

When walking the tree for `mode=semantics`:

1. Skip nodes where `isInvisible == true` (empty rect or zeroed transform)
2. Skip nodes where the `isHidden` flag bit is set (`flags & (1<<13) != 0`)
3. Nodes where `mergeAllDescendantsIntoThisNode == true` carry the merged
   label/value of their subtree — treat them as leaf nodes and don't recurse
4. Nodes where `isMergedIntoParent == true` have already been rolled up — skip
   or de-duplicate

---

## 7. Notes on `flutter_driver`

`flutter_driver` requires the app to import the driver package and register
`ext.flutter.driver.*` service extensions. It is not usable from an MCP server
that must work with unmodified apps.

One useful pattern it documents: after calling `ensureSemantics()`, wait for the
next frame before reading the tree:

```dart
SchedulerBinding.instance.addPostFrameCallback((_) {
  // semantics tree is now populated and up to date
});
```

The current implementation calls `enableSemantics()` in `_connectVmService` and
fails open. If the tree is empty on the first `get_semantics` call, the agent
should retry after a screenshot or hot reload (both of which synchronize on a
rendered frame).

---

## 8. Further Reading

See `DESIGN.md` for the full tool surface, implementation status, and design
rationale. This document focuses on the underlying protocol and data structures.
