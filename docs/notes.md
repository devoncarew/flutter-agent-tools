# General TODO notes

## Flutter UI Agent

- [x] make sure we get stdout from apps
- [x] make sure we get stderr from apps
- [x] make sure we get exceptions from apps
- [x] is SemanticsBinding.performSemanticsAction() a good way to drive the UI?
- [x] should we repartition the commands? [done]

## From feedback

- [ ] make session_id optional? There's generally only ever going to be one
      session
- [ ] when starting a session, send back a short how-to guide?
- [ ] include information about helpful source modifications:
  - adding semantic nodes helps traversal (and also screen readers, ...)
  - modifying the source to improve getting and setting routes
- [ ] ship a small 'agents tools' library? That could add vm service extension
      methods which we could then call

- Is the 'packages' tool better as one tool with three modes or three separate
  tools?
