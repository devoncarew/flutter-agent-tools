# General TODO notes

## Flutter UI Agent

- [x] make sure we get stdout from apps
- [x] make sure we get stderr from apps
- [x] make sure we get exceptions from apps
- [x] is SemanticsBinding.performSemanticsAction() a good way to drive the UI?
- [x] should we repartition the commands?

## Feedback-01

- [x] split the api mcp server into three tool commands
- [x] consider making the session_id optional; if one session just use it
- [ ] when starting a session, send back a short how-to guide?
- [x] investigate why genertics in expr eval are getting HTML-entity-encoded
      (`&lt;Type&gt;`)
- [ ] allow `flutter_navigate` to pass `extra` args; support a JSON `extra`
      payload? Not sure this is possible; would need a custom vm service
      extension method

## Feedback-02

- [x] should document that `tap` relies on the `action:tap` being present in the
      semantics node.
- [x] call SemanticsBinding.binding.semanticsEnabled to check, then call
      ensureSemantics() and WidgetsBinding.instance.scheduleFrame() if necessary
- [x] `tap` with `node_id: 5` (an integer) failed with: "Value `5` is not of
      type `int` at path #root["node_id"]"; `node_id` parameter appears to have
      a type mismatch in the tool schema or server-side handling; this looks to
      be an error from the package:dart_mcp layer before marshalling params to
      us
- [x] First call to `inspect_layout` with `subtree_depth: 3` failed with: "Value
      `3` is not of type `int` at path #root["subtree_depth"]"; Same pattern as
      the `node_id` issue above — likely the same underlying schema problem.

## How-to

- adding semantic nodes helps traversal (and also screen readers, ...)
- modifying the source to improve getting and setting routes?

- [x] explore what an in-line package could provide; would it be a big enough
      win to recommend it? better semantic tree retrieval, better routing
      support, ...; package:slipstream_agent / package:slipstream_support

## Logging

- Claude Code does not appear to forward notifications/message MCP events into
  the model context at all.
- Once we do get log messages to the model we should make sure they're not too
  verbose.

- [ ] resolution: design and add an 'output' tool; get most recent stdout and
      errors
