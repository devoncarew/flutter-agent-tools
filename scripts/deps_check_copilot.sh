#!/usr/bin/env bash

# GitHub Copilot 'preToolUse' hook entry point for dependency health checks.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

INPUT=$(cat)

# Detect mode from the hook input JSON (Copilot has no native matcher/if filtering).
if printf '%s' "$INPUT" | grep -qF '"toolName":"bash"' && \
   printf '%s' "$INPUT" | grep -qF 'pub add'; then
  MODE=pub-add
elif printf '%s' "$INPUT" | grep -qF '"toolName":"edit"' && \
     printf '%s' "$INPUT" | grep -qF 'pubspec.yaml'; then
  MODE=pubspec-guard
else
  exit 0
fi

if ! command -v dart &>/dev/null; then exit 0; fi
printf '%s' "$INPUT" | (cd "$PLUGIN_ROOT" && exec dart run "bin/deps_check.dart" --agent=copilot "--mode=$MODE")
