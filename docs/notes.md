# General TODO notes

## Flutter UI Agent

- [x] make sure we get stdout from apps
- [x] make sure we get stderr from apps
- [x] make sure we get exceptions from apps
- [x] is SemanticsBinding.performSemanticsAction() a good way to drive the UI?
- [ ] should we repartition the commands?
  - flutter_get_route / flutter_set_route (go_router only)
  - flutter_route_get flutter_route_set
  - flutter_get_semantics (for the semantics tree) / flutter_interact
  - flutter_semantics_query / flutter_semantics_interact
  - flutter_query_ui (but just for the widget tree)
