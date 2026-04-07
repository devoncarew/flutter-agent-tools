#!/usr/bin/env bash

# start_dep_check.sh
#
# PreToolUse hook entry point for dependency health checks.
#
# Uses $0 to locate itself, so it works regardless of how ${CLAUDE_PLUGIN_ROOT}
# is resolved by the host — the script is its own source of truth for the
# plugin root directory.
#
# All arguments are forwarded to dep_check.dart (e.g. --mode=pub-add).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

(cd "$PLUGIN_ROOT" && exec dart run "bin/deps_check.dart" "$@")
