// Unofficial blocklist of packages that are effectively abandoned or
// superseded, but are not officially marked `isDiscontinued` on pub.dev.

// ## Criteria for inclusion
//
// A package belongs here if it meets **at least two** of the following:
//
// - No pub.dev publish in ~2+ years (check `latest.published` in the API).
// - The original author has publicly moved on (new package, archived repo,
//   explicit blog post / README note).
// - A well-maintained community fork or successor exists and is widely adopted.
// - The package is known to cause agents to write code that fails at runtime
//   (e.g. API shape changed significantly in the successor).
//
// ## What does NOT belong here
//
// - Stable, mature packages that simply don't need frequent releases.
// - Packages that are officially discontinued (pub.dev already covers those).
// - Anything where we're not confident — omit it rather than false-positive.
//
// ## How to update
//
// Add an entry below and open a PR. Include:
//
// - The exact pub.dev package name.
// - A `reason` string (one sentence, terse — shown directly to the agent).
// - A `suggestion` string naming the recommended replacement, if one exists.
//
// The `reason` should read naturally after "Warning: 'pkg' — reason".
// Example: "last published June 2022; use hive_ce (community edition fork)"
//
// Do not add entries speculatively. Each entry costs agent attention.

/// Packages that are effectively abandoned or superseded, but not officially
/// discontinued on pub.dev.
const List<BlocklistEntry> unofficialBlocklist = [
  // Hive related (local NoSQL database)
  BlocklistEntry(
    package: 'hive',
    reason: 'last published June 2022; has a community maintained fork',
    suggestion: 'hive_ce',
  ),
  BlocklistEntry(
    package: 'hive_flutter',
    reason: 'last published June 2021; has a community maintained fork',
    suggestion: 'hive_ce_flutter',
  ),
  BlocklistEntry(
    package: 'hive_generator',
    reason: 'last published August 2023; has a community maintained fork',
    suggestion: 'hive_ce_generator',
  ),
];

/// A single entry in the unofficial blocklist.
class BlocklistEntry {
  const BlocklistEntry({
    required this.package,
    required this.reason,
    this.suggestion,
  });

  /// The pub.dev package name.
  final String package;

  /// One-sentence explanation shown to the agent.
  final String reason;

  /// The recommended replacement package name, if one exists.
  final String? suggestion;
}
