#!/usr/bin/env bash

# deps_check.sh
#
# PreToolUse hook entry point for dependency health checks.
#
# Uses $0 to locate itself, so it works regardless of how ${CLAUDE_PLUGIN_ROOT}
# is resolved by the host — the script is its own source of truth for the
# plugin root directory.
#
# All arguments are forwarded to deps_check.dart (e.g. --mode=pub-add).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Shell-level fast exit for pub-add mode: read stdin once, then skip the Dart
# VM entirely unless the command looks like a pub add invocation. Starting a
# fresh Dart VM for every Bash tool call is expensive; this keeps the hook
# near-instant for the vast majority of calls.
if [[ "$*" == *"--mode=pub-add"* ]]; then
  INPUT=$(cat)
  if ! printf '%s' "$INPUT" | grep -qF 'pub add'; then
    exit 0
  fi
  if ! command -v dart &>/dev/null; then exit 0; fi
  printf '%s' "$INPUT" | (cd "$PLUGIN_ROOT" && exec dart run "bin/deps_check.dart" "$@")
  exit 0
fi

if [[ "$*" == *"--mode=pubspec-guard"* ]]; then
  INPUT=$(cat)
  if ! printf '%s' "$INPUT" | grep -qF 'pubspec.yaml'; then
    exit 0
  fi
  if ! command -v dart &>/dev/null; then exit 0; fi
  printf '%s' "$INPUT" | (cd "$PLUGIN_ROOT" && exec dart run "bin/deps_check.dart" "$@")
  exit 0
fi

if ! command -v dart &>/dev/null; then exit 0; fi
(cd "$PLUGIN_ROOT" && exec dart run "bin/deps_check.dart" "$@")
