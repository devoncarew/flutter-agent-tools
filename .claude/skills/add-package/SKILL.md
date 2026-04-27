---
name: add-package
description: >
  Safe workflow for adding a Dart or Flutter package dependency. Covers how to
  read pub command output for discontinued and outdated-version warnings, and
  what corrective action to take for each.
user-invocable: false
trigger: >
  TRIGGER when: about to add a Dart or Flutter package dependency — running
  flutter pub add, dart pub add, or editing pubspec.yaml to add a new package.
  Also trigger when choosing a specific version constraint for a package. SKIP:
  upgrading existing packages (pub upgrade), removing packages, or pub commands
  that don't introduce a new dependency.
---

# Adding a Dart/Flutter Package Dependency

## Preferred approach

Use `flutter pub add <package>` (or `dart pub add`) rather than editing
`pubspec.yaml` directly. The pub command output is the primary signal for
package health; direct edits bypass it.

## Read pub output after every add

After running `pub add`, read the output carefully before proceeding. Two
classes of problem appear inline:

### Discontinued packages

```
+ flutter_markdown 0.7.7+1 (discontinued replaced by flutter_markdown_plus)
...
1 package is discontinued.
```

Action:

- If a replacement is listed: remove the discontinued package and add the
  replacement instead (`flutter pub remove <pkg>` then
  `flutter pub add <replacement>`).
- If no replacement is listed: find a well-maintained alternative before
  proceeding.

### Version pinned behind current major

```
+ lints 4.0.0 (6.1.0 available)
...
4 packages have newer versions incompatible with dependency constraints.
```

The `(X.Y.Z available)` annotation on a package you just added means the version
you requested is behind the current release — often by a major version.

Action:

- Run `flutter pub outdated` to see the structured breakdown:

  ```
  Package Name  Current  Upgradable  Resolvable  Latest
  lints         *4.0.0   *4.0.0      6.1.0       6.1.0
  ```

- If a direct dependency you just added shows a major-version gap between
  Current and Latest, remove the version pin or update the constraint to the
  current major (`flutter pub add 'lints:^6.0.0'`).
- Transitive dependency gaps are generally not actionable — note them but don't
  block on them.

## When editing pubspec.yaml directly

If you add a dependency by editing `pubspec.yaml` instead of using `pub add`,
run `flutter pub get` immediately after and apply the same output-reading rules.
