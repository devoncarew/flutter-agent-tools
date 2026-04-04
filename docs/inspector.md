# Flight Check: Flutter Runtime Inspection Guide for AI Agents

## 1. Conceptual Overview: The Three Trees

To effectively debug and interact with a Flutter app—whether running as a desktop app or on an emulated mobile device—agents must understand that Flutter's UI is not a single DOM. It is composed of interconnected trees:

1.  **The Widget Tree (Configuration):** This is the code the developer writes. Widgets are immutable, lightweight blueprints. _Agents cannot debug layout issues by looking solely at the Widget tree._
2.  **The Element Tree (Lifecycle & State):** Represents the actual instances of widgets mounted on the screen. It holds the `State` objects.
3.  **The Render Tree (Geometry & Layout):** This is the engine room. Render objects handle painting, sizing, constraints, and hit-testing. **When debugging overflows, unbounded heights, or invisible widgets, the Render Tree is the single source of truth.**
4.  **The Semantics Tree (Interaction & Accessibility):** Because Render objects do not always have human-readable identifiers, the Semantics tree is how tools find logical elements like "buttons" and "text fields." This tree is strictly required for driving UI interactions.

## 2. Accessing Runtime State: The Flutter Inspector (Read-Only)

The Dart VM Service Protocol exposes `ext.flutter.inspector` extensions. These calls return `DiagnosticsNode` JSON objects, representing the current state of the UI.

### Key Service Calls

- `ext.flutter.inspector.getRootWidgetSummaryTree`: Fetches a lightweight overview of the current UI. Use this to get the `valueId` of the root node or to find a specific widget in the hierarchy.
- `ext.flutter.inspector.getDetailsSubtree(diagnosticableId: String)`: The heavy lifter. Returns the exhaustive list of properties, constraints, and render objects for a specific node.

### Navigating `DiagnosticsNode` Irregularities

Inspector data is generated via Dart's `debugFillProperties`, meaning property names are polymorphic.

- **Finding Sizing:** Inside a `renderObject` property array, dimensions might be named `"size"`, `"view size"`, or `"geometry"`.
- **Extracting Values:** Values are often stringified descriptions rather than native JSON types. Constraints must be parsed from strings like `"BoxConstraints(w=400.0, h=800.0)"`.

## 3. The Alternative Read Path: VM Service `evaluate`

Because Inspector extensions are string-heavy and sometimes brittle to parse, agents can use the core VM service `evaluate` RPC to execute arbitrary Dart code on the running app.

**Example: Getting Exact Screen Dimensions**
Instead of parsing the root RenderView's `"view size"` string, evaluate this directly on the main isolate to get the exact window/emulator dimensions:

```dart
WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.toString()
```

## 4. Driving UI Interactions: The "Zero-Modification" Playbook

To interact with the app (tapping, typing, scrolling), an agent needs to map a semantic intent ("Tap the Login button") to an action.

### Why we do NOT use `ext.flutter.driver`

The `flutter_driver` framework exposes easy-to-use remote control endpoints. However, it requires the developer to import testing libraries and modify their `main.dart` to enable the extension. Because this tool must operate on standard, unmodified application code, **the driver extensions are unavailable.**

### Why we do NOT use `debugDumpSemanticsTree...`

While these Inspector methods exist, they return ASCII-art formatted strings, not structured JSON. They require highly fragile Regex to parse indentation levels and are unsuitable for reliable agent automation.

### The Pure VM Service Approach

To achieve interaction without modifying the host app, agents must synthesize interactions via the `evaluate` RPC using the following three steps:

**Step A: Wake up the Semantics Tree**
Flutter disables the semantics tree by default to save resources. Evaluate this Dart expression to turn it on:

```dart
RendererBinding.instance.ensureSemantics()
```

**Step B: Query the Semantics Tree for Geometry**
Send a Dart script via `evaluate` that traverses `RendererBinding.instance.pipelineOwner.semanticsOwner.rootSemanticsNode`. The script should return a clean JSON string containing semantic labels, node IDs, and their absolute coordinate bounds on the screen.

**Step C: Synthesize the Interaction (The "Ghost Finger")**
Once the agent knows a target is located at `(x: 150, y: 300)`, it injects native pointer events directly into Flutter's gesture binding via `evaluate`:

```dart
GestureBinding.instance.handlePointerEvent(PointerDownEvent(pointer: 1, position: Offset(150.0, 300.0)));
GestureBinding.instance.handlePointerEvent(PointerUpEvent(pointer: 1, position: Offset(150.0, 300.0)));
```

## 5. Optimizing for LLM Context Windows

Flutter apps have thousands of active nodes. Sending raw JSON dumps will instantly blow out an agent's context window. The MCP server acts as a strict filter.

### Strategies for Efficiency

1.  **Targeted Queries:** Never dump the whole tree. Only fetch subtrees for the `valueId` the agent specifically requests.
2.  **Tree Shaking the JSON:** The server strips out styling properties (colors, fonts, borders). A "Layout Context" response should only include: Widget Name, Widget ID, parent/child relationships, and Layout Data (Constraints, Size, Flex factor).
3.  **Regex / Path Querying:** Use pseudo-selectors in the MCP server so agents can query specific anomalies without full traversals (e.g., `flutter_query_ui(query: "find: RenderFlex where overflow == true")`).

## 6. MCP Tool Architecture Reference

The following tools bridge the gap between the LLM and the running Flutter process.

### Session & Lifecycle

- `flutter_launch_app(target: String?, device: String?) → String`: Starts the app via `flutter run --machine` and establishes the VM service connection. Returns a `session_id`.

### Inspection & Debugging (Read)

- `flutter_query_ui(session_id: String, query: String) → String`: Fetches heavily filtered JSON representing the UI tree.
- `flutter_get_exceptions(session_id: String) → List<String>`: Returns a stack of recent rendering or layout exceptions.
- `flutter_inspect_layout(session_id: String, widget_id: String) → String`: **[High Value]** Returns _only_ the `BoxConstraints`, `Size`, and incoming flex parameters for a specific node to debug overflows.

### Interaction & Automation (Write)

_These tools utilize the Semantics + GestureBinding injection strategy outlined in Section 4._

- `flutter_tap(session_id: String, semantics_label: String) → void`
- `flutter_inject_text(session_id: String, semantics_label: String, text: String) → void`
- `flutter_scroll_to(session_id: String, semantics_label: String) → void`

### Visual Verification

- `flutter_take_screenshot(session_id: String, pixel_ratio: String?) → String`: Captures the current frame via the VM service. Crucial for multimodal agents to visually verify that a layout fix was successful.
