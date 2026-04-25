#!/usr/bin/env bash

# Gemini CLI 'BeforeTool' hook entry point for dependency health checks.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

INPUT=$(cat)

if [[ "$*" == *"--mode=pub-add"* ]]; then
  # Shell-level fast exit for pub-add mode.
  if ! printf '%s' "$INPUT" | grep -qF 'pub add'; then
    exit 0
  fi
elif [[ "$*" == *"--mode=pubspec-guard"* ]]; then
  # Shell-level fast exit for pubspec-guard mode.
  if ! printf '%s' "$INPUT" | grep -qF 'pubspec.yaml'; then
    exit 0
  fi
fi

if ! command -v dart &>/dev/null; then exit 0; fi
printf '%s' "$INPUT" | (cd "$PLUGIN_ROOT" && exec dart run "bin/deps_check.dart" --agent=gemini "$@")
