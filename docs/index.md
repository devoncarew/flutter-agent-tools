# Documentation Index

Agent navigation guide. Each entry describes what the document covers and when
to read it.

## Architecture and Design

- [DESIGN.md](DESIGN.md) — System overview: problem statement, distribution
  (Claude Code / Gemini CLI / GitHub Copilot), and rationale for each of the
  three tools (deps hook, packages MCP, inspector MCP). Read first for
  architectural context before adding or changing any tool.

- [inspector_design.md](inspector_design.md) — Inspector MCP implementation
  details: device auto-selection logic, `get_route` capabilities and
  limitations, go_router path enrichment via VM evaluate, and the `navigate`
  fallback chain. Read when working on `run_app`, `get_route`, or `navigate`.

- [slipstream_agent.md](slipstream_agent.md) — The optional companion package:
  registered service extensions, ghost overlay, detection via
  `ext.slipstream.ping`, and source file map. Read when working on companion
  detection or `ext.slipstream.*` service extensions.

## Inspector Protocol Reference

- [flutter_inspection.md](flutter_inspection.md) — Flutter runtime concepts: the
  four-tree model, VM service `evaluate` patterns, semantics interaction via
  `performSemanticsAction`, `SemanticsFlag` and `SemanticsAction` bitmask
  tables, and tree-walking filter criteria. Read when working on tools that
  touch the semantics tree or layout debugging.

- [inspector_protocol.md](inspector_protocol.md) — Inspector protocol specifics
  from DevTools source: full `ext.flutter.inspector.*` extension list, critical
  quirks (`groupName` vs `objectGroup`, boolean params as strings, `valueId` ≠
  VM object ID), `DiagnosticsNode` JSON shape, `Flutter.Navigation` event
  handling, and VM service extension event list. Read when implementing or
  debugging inspector protocol calls.

## Agent Guidance

- [skill.md](skill.md) — Draft skill document with practical agent workflows,
  tool selection guidance, and non-obvious gotchas. Read when authoring or
  updating the plugin skill.

- [smoke-test.md](smoke-test.md) — Prompt for smoke-testing the plugin end to
  end. Used for regression testing and onboarding new testers.

- [study-setup.md](study-setup.md) — Setup script and prompt for user studies.
  Creates a fresh Flutter app and walks through the full plugin workflow.

## Other

- [privacy_policy.md](privacy_policy.md) — Plugin privacy policy.
