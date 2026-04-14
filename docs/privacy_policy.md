# Privacy Policy

**Flutter Slipstream**
Last updated: April 2026

## Overview

Flutter Slipstream does not collect, store, or transmit any personal
information. This policy describes the one network request the tool makes and
what it sends.

## Data collected

None. Flutter Slipstream does not collect analytics, usage telemetry, crash
reports, or any other personal or identifying information.

## Network requests

The package-currency hook contacts [pub.dev](https://pub.dev) to check whether
packages referenced in a project's `pubspec.yaml` are current. The only
information sent is package names (e.g. `http`, `provider`) and version
constraints. No user identity, project name, file paths, or other metadata are
included. These requests are subject to
[Google's privacy policy](https://policies.google.com/privacy).

All other operations — widget tree inspection, screenshots, evaluate, semantics
queries — communicate exclusively with the Flutter app running on the local
machine via the Dart VM service. No data leaves the machine.

## Changes

If this policy changes materially, the "Last updated" date above will be
updated and a note will appear in the
[changelog](../CHANGELOG.md).

## Contact

Questions or concerns? Open an issue at
<https://github.com/devoncarew/flutter-slipstream/issues>.

---

*Flutter Slipstream is maintained by Devon Carew.*
