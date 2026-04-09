# Slipstream Companion Package: Design Document

## Overview

`slipstream` is designed to provide zero-configuration runtime inspection of
Flutter applications via the Dart VM Service. By default, it relies on
evaluating Dart strings to extract state and inject interactions.

While this baseline is powerful, agents occasionally hit the limits of
"stringly-typed" evaluations or struggle to navigate complex, custom routing and
UI structures.

The **Slipstream Companion Package** (`slipstream_agent`) is an optional,
strictly opt-in `dev_dependency` that developers (or their AI agents) can
install into the host Flutter app. It upgrades the connection from external
observation to internal cooperation, providing robust typed endpoints, visual
feedback, and deeper framework hooks.

## Core Philosophy

1.  **Zero-Config Baseline:** `slipstream` MUST remain fully functional without
    this package. The package unlocks _enhanced_ capabilities and reliability,
    but is never strictly required for basic inspection and interaction.
2.  **Explicit Opt-In:** Agents are strictly forbidden from modifying
    `pubspec.yaml` to install this package without explicit human consent. The
    MCP server instructions will dictate that the agent must explain the
    benefits and ask the developer before installation.
3.  **Development Only:** The package relies on `dart:developer` and debugging
    APIs. It must be designed to compile out or aggressively tree-shake in
    release builds (e.g., heavily utilizing `kDebugMode`).

## Motivations & Features

### 1. Robust Service Extensions (No more `evaluate` strings)

Relying on `vmService.evaluate` with raw strings is fragile and prone to
breaking across Flutter versions or due to LLM formatting errors.

- **Feature:** The package registers strongly-typed JSON RPC endpoints via
  `dart:developer`'s `registerExtension` (e.g., `ext.slipstream.tap`,
  `ext.slipstream.get_layout`).
- **Benefit:** The MCP server can send structured JSON requests. The package
  executes the complex Dart logic internally, guaranteeing type safety and
  returning clean JSON responses.

### 2. The "Ghost Overlay" (Visual Intent)

When an agent is silently querying the UI or injecting taps via the VM service,
the human developer has no idea what the agent is targeting until a screenshot
is taken or the app state changes.

- **Feature:** The package injects a `SlipstreamOverlay` widget at the root of
  the app. When the MCP server calls `ext.slipstream.inspect(widget_id)`, the
  package temporarily draws a highly visible bounding box (the "Ghost Overlay")
  around that widget on the actual device screen.
- **Benefit:** Real-time visual feedback. The developer can literally see what
  the AI is "looking at" or interacting with.

### 3. Unified Routing Adapter

The default `navigate` tool relies purely on `GoRouter`.

- **Feature:** The package initialization accepts a router interface adapter:
  `SlipstreamAgent.init(router: myRouter)`.
- **Benefit:** Agents can reliably navigate apps using `auto_route`, `beamer`,
  or vanilla `Navigator 2.0` without needing to guess the implementation details
  or inject custom routing scripts.

### 4. Advanced UI Finders

While the agent's addition of Semantics nodes aids accessibility, sometimes an
agent just needs to tap a specific widget without waiting for a developer to
approve a Semantics PR.

- **Feature:** Exposing `flutter_test`-style Finders at runtime via the service
  extension.
- **Benefit:** Agents can issue commands like
  `ext.slipstream.interact({ "action": "tap", "finder": "byKey", "value": "login_button" })`.
  The package traverses the Element tree, resolves the `RenderBox` geometry, and
  synthesizes the exact pointer events.

### 5. Structured Framework Telemetry

Currently, the MCP server recieves structured `Flutter.Error` events and sends
formatted summaries to the MCP client. However, when in-process we could hook
into and send other useful framework events.

- **Feature:** The package hooks into
  `PlatformDispatcher.instance.onWindowResolutionChanged` and other core
  framework bindings.
- **Benefit:** It directly broadcasts clean, structured JSON telemetry back over
  the VM service connection, agent is notified of useful framework events and
  state changes.

## Mechanics & Integration

### Installation

The package is added as a development dependency.

```yaml
dev_dependencies:
  slipstream_agent: ^1.0.0
```

### Initialization

The developer (or agent) modifies `main.dart` to initialize the agent, safely
wrapping it to prevent production leakage.

```dart
import 'package:flutter/foundation.dart';
import 'package:slipstream_agent/slipstream_agent.dart';

void main() {
  if (kDebugMode) {
    SlipstreamAgent.init(
      enableOverlay: true,
      router: GoRouterAdapter(appRouter),
    );
  }
  runApp(const MyApp());
}
```

### The Agent Workflow

1.  **Session Start:** When `run_app` is called, the `inspector` MCP server
    connects to the VM Service and attempts to call `ext.slipstream.ping`.
2.  **Fallback Mode:** If the ping fails (method not found), the MCP server
    falls back to the default `evaluate` string approach.
3.  **Enhanced Mode:** If the ping succeeds, the MCP server updates its internal
    state to route all tools (like `inspect_layout`, `tap`, `navigate`) through
    the `ext.slipstream.*` endpoints.
4.  **The Ask:** If an agent encounters repeated failures using the default
    tools (e.g., cannot find a semantic node, routing fails), its system prompt
    instructs it to ask the user: _"I'm having trouble interacting with this UI.
    Would you like me to install the `slipstream_agent` companion package to
    enable direct element targeting and visual overlays?"_
