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
`DiagnosticableTreeNode` can be passed directly to `flutter_inspect_layout` for
a deeper drill-down.

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

## 4. Driving UI Interactions: The "Zero-Modification" Playbook

To interact with the app (tapping, typing, scrolling), an agent needs to map a
semantic intent ("Tap the Login button") to an action.

### Why we do NOT use `ext.flutter.driver`

The `flutter_driver` framework exposes easy-to-use remote control endpoints.
However, it requires the developer to import testing libraries and modify their
`main.dart` to enable the extension. Because this tool must operate on standard,
unmodified application code, **the driver extensions are unavailable.**

### Why we do NOT use `debugDumpSemanticsTree...`

While these Inspector methods exist, they return ASCII-art formatted strings,
not structured JSON. They require highly fragile Regex to parse indentation
levels and are unsuitable for reliable agent automation.

### The Pure VM Service Approach

To achieve interaction without modifying the host app, agents must synthesize
interactions via the `evaluate` RPC using the following three steps:

**Step A: Wake up the Semantics Tree** Flutter disables the semantics tree by
default to save resources. Evaluate this Dart expression to turn it on:

```dart
RendererBinding.instance.ensureSemantics()
```

**Step B: Query the Semantics Tree for Geometry** Send a Dart script via
`evaluate` that traverses
`RendererBinding.instance.pipelineOwner.semanticsOwner.rootSemanticsNode`. The
script should return a clean JSON string containing semantic labels, node IDs,
and their absolute coordinate bounds on the screen.

**Step C: Synthesize the Interaction (The "Ghost Finger")** Once the agent knows
a target is located at `(x: 150, y: 300)`, it injects native pointer events
directly into Flutter's gesture binding via `evaluate`:

```dart
GestureBinding.instance.handlePointerEvent(PointerDownEvent(pointer: 1, position: Offset(150.0, 300.0)));
GestureBinding.instance.handlePointerEvent(PointerUpEvent(pointer: 1, position: Offset(150.0, 300.0)));
```

### Other alternatives

- Ship a small, targeted driver style package (`tap`, `waitFor`, `enter_text`,
  and `get_text`, ...) that the user or agent would install. This is simple but
  would represent a friction point.
- Provide the agent a description of a library they could provision (write to
  `lib/src/agent_debug_tools.dart`) in order to better use the MCP service.

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

## 6. Further Reading

See `DESIGN.md` for the full tool surface, implementation status, and design
rationale. This document focuses on the underlying protocol and data structures.
