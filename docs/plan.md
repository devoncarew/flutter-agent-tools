# Implementation plan: `package_info` kind parameter

## Context

The `package_info` MCP tool currently returns a package version, a list of
public library filenames, and the raw source of the main entry-point file.
The goal is to replace this with a `kind`-dispatched API that gives agents
progressively more detail:

| `kind`          | Returns                                                               |
| --------------- | --------------------------------------------------------------------- |
| `package_summary` | Version, entry-point import, README excerpt, exported name groups   |
| `library_stub`  | Full public API for one library as a Dart stub (no bodies)            |
| `class_stub`    | Stub for one named class/mixin/extension from a library               |
| `example`       | Example file contents or extracted `/// ```dart` snippets (deferred) |

Infrastructure already complete: `PackageResolver` resolves a library URI to a
`LibraryElement`; `emitLibraryStub()` emits a full Dart stub from one;
`exportedNamesSummary()` produces a grouped name list.

---

## Step 1 — Revamp tool schema; implement `package_summary` ✓

**Files:** `lib/src/shorthand/package_info.dart`, `lib/src/shorthand/resolver.dart`

- Added `kind` (required), `library` (optional), `class` (optional) to the
  tool's `inputSchema`; `handle()` dispatches on `kind`.
- `package_summary` returns: version header, entry-point import, README first
  paragraph, public library list, exported name groups from the main library.
- Single-entry `PackageResolver` cache in `PackageInfoTool`, keyed on
  `(packageDir.path, packageConfigFile)`; disposed on eviction.
- Fixed `exportedNamesSummary()` in `resolver.dart` to capture top-level
  variables (they appear as `GetterElement` in the export namespace, not
  `TopLevelVariableElement`).

---

## Step 2 — Implement `library_stub`

**Files:** `lib/src/shorthand/package_info.dart`

- Add `_libraryStub()` method, called when `kind == 'library_stub'`.
- Validate that `library` param is present (e.g. `package:http/http.dart`);
  return an error if absent.
- Use the cached `PackageResolver` to resolve the library → `LibraryElement`.
- Call `emitLibraryStub(library)` and return the result as text.
- Update the tool description to document `library_stub` and the `library`
  param.

---

## Step 3 — Implement `class_stub`

**Files:** `lib/src/shorthand/stub_emitter.dart`,
`test/shorthand/stub_emitter_golden_test.dart`,
`lib/src/shorthand/package_info.dart`

- Add `emitElementStub(LibraryElement library, String name) → String?` to
  `stub_emitter.dart`. Searches the export namespace for a matching class,
  mixin, extension, or enum by name; emits just that element; returns null if
  not found.
- Add golden tests for `emitElementStub` covering: class, abstract class,
  mixin, extension, enum.
- Add `_classStub()` handler in `package_info.dart`:
  - Requires both `library` and `class` params.
  - Resolves the library, calls `emitElementStub()`, returns result or an
    informative error if the name isn't found.
- Update tool description.

---

## Deferred

- **`example` kind:** read files from `example/`, or extract `/// ```dart`
  snippets from doc comments. Low priority — agents can request example files
  directly via the `Read` tool.
- **Cross-library class search:** allow `class_stub` without specifying
  `library` by searching all public libraries. Adds complexity; deferred until
  there's clear demand.
