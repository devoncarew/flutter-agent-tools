# General TODO notes

## Flutter UI Agent

- [x] make sure we get stdout from apps
- [x] make sure we get stderr from apps
- [x] make sure we get exceptions from apps
- [x] is SemanticsBinding.performSemanticsAction() a good way to drive the UI?
- [x] should we repartition the commands?

## From feedback

- [x] split the api mcp server into three tool commands
- [ ] consider making the session_id optional; if one session just use it
- [ ] when starting a session, send back a short how-to guide?
- [ ] investigate why genertics in expr eval are getting HTML-entity-encoded
      (`&lt;Type&gt;`)
- [ ] allow `flutter_navigate` to pass `extra` args; support a JSON `extra`
      payload? Not sure this is possible; would need a custom vm service
      extension method

### How-to

- adding semantic nodes helps traversal (and also screen readers, ...)
- modifying the source to improve getting and setting routes?
- ship a small 'agents tools' library?
  - it could add vm service extension methods which we could then call
  - improved semantic node traversal
