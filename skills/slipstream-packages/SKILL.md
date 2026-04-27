---
name: slipstream-packages
description: >-
  This skill should be used when about to write Dart or Flutter code that calls
  into a pub package whose API is uncertain — the package is unfamiliar, or its
  version in pubspec.lock may be newer than training data. Also load when
  hitting an unexpected compile error or type mismatch on a package import. Skip
  for code that only uses the Dart SDK (dart:*) and packages already verified
  this session.
user-invocable: false
---

# Dart Package API Lookup

Training-data summaries for pub packages are often subtly out-of-date: incorrect
parameter names, missing required/optional distinctions, wrong constructor
shapes, renamed or removed APIs. The `packages` tools read directly from the
local pub cache — exact signatures, always matches `pubspec.lock`, no network
required.

## Call sequence

1. `package_summary(project_directory, package)` — always start here. Returns
   version, entry-point import, library list, and exported name groups. Often
   enough to confirm the right import path and top-level names.
2. `library_stub(project_directory, package, library_uri)` — full public API for
   one library as Dart signatures (no bodies, no private members). Use when you
   need exact constructor shapes, named parameter names, or return types.
3. `class_stub(project_directory, package, library_uri, class)` — single class
   stub including inherited and mixin-contributed members. Use when you know
   exactly which class you need.

`project_directory` is the absolute path to the Dart/Flutter project (the
directory containing `pubspec.yaml`). Run `dart pub get` first if
`.dart_tool/package_config.json` is missing.

## Limitation

Constants values are not shown in stubs.
