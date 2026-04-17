#!/usr/bin/env bash

# deps_check_gemini.sh
#
# BeforeTool hook entry point for dependency health checks (Gemini CLI).
#
# Gemini input differs from Claude input: tool arguments are in
# 'tool_arguments' rather than 'tool_input', tool names differ
# ('run_shell_command' vs 'Bash', 'write_file'/'replace' vs 'Write'/'Edit'),
# and output must be JSON rather than plain text.
#
# Uses $0 to locate itself, so it works regardless of how ${extensionPath}
# is resolved by the host.
#
# All arguments are forwarded to deps_check_gemini.dart (e.g. --mode=pub-add).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Shell-level fast exit for pub-add mode.
if [[ "$*" == *"--mode=pub-add"* ]]; then
  INPUT=$(cat)
  if ! printf '%s' "$INPUT" | grep -qF 'pub add'; then
    exit 0
  fi
  if ! command -v dart &>/dev/null; then exit 0; fi
  printf '%s' "$INPUT" | (cd "$PLUGIN_ROOT" && exec dart run "bin/deps_check_gemini.dart" "$@")
  exit 0
fi

# Shell-level fast exit for pubspec-guard mode.
if [[ "$*" == *"--mode=pubspec-guard"* ]]; then
  INPUT=$(cat)
  if ! printf '%s' "$INPUT" | grep -qF 'pubspec.yaml'; then
    exit 0
  fi
  if ! command -v dart &>/dev/null; then exit 0; fi
  printf '%s' "$INPUT" | (cd "$PLUGIN_ROOT" && exec dart run "bin/deps_check_gemini.dart" "$@")
  exit 0
fi

if ! command -v dart &>/dev/null; then exit 0; fi
(cd "$PLUGIN_ROOT" && exec dart run "bin/deps_check_gemini.dart" "$@")
