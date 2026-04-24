#!/usr/bin/env bash

# Claude PreToolUse hook entry point for dependency health checks.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

INPUT=$(cat)

# Exit early if no 'pub add' (safety net for complex Bash commands).
if [[ "$*" == *"--mode=pub-add"* ]] && ! printf '%s' "$INPUT" | grep -qF 'pub add'; then
  exit 0
fi

if ! command -v dart &>/dev/null; then exit 0; fi
printf '%s' "$INPUT" | (cd "$PLUGIN_ROOT" && exec dart run "bin/deps_check_claude.dart" "$@")
