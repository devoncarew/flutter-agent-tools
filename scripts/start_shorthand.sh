#!/usr/bin/env bash

# start_shorthand.sh
#
# Entry point for the dart-api MCP server (package API summarization).
#
# Uses $0 to locate itself, so it works regardless of how ${CLAUDE_PLUGIN_ROOT}
# is resolved by the host — the script is its own source of truth for the
# plugin root directory.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

(cd $PLUGIN_ROOT && exec dart run "bin/shorthand_mcp.dart")
