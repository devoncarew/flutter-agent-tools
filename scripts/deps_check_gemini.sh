#!/usr/bin/env bash

# Gemini CLI 'BeforeTool' hook entry point for dependency health checks.

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
