#!/usr/bin/env bash
# dep_health_check.sh
#
# PreToolUse hook: intercepts Bash tool calls and validates any package being
# added via `flutter pub add` or `dart pub add` against pub.dev before the
# command runs.
#
# Claude Code passes the tool input as JSON on stdin:
#   { "tool_name": "Bash", "tool_input": { "command": "flutter pub add some_pkg" } }
#
# Exit 0  → allow the command to proceed
# Exit 1  → block the command (Claude will see the output as the reason)

set -euo pipefail

# ── Helpers ──────────────────────────────────────────────────────────────────

require() {
  if ! command -v "$1" &>/dev/null; then
    echo "flutter-agent-tools: dep_health_check requires '$1' but it was not found." >&2
    exit 0  # Fail open: don't block the agent over a missing tool
  fi
}

require jq
require curl

# ── Parse stdin ───────────────────────────────────────────────────────────────

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
command_str=$(echo "$input" | jq -r '.tool_input.command // empty')

# Only act on Bash tool calls
[[ "$tool_name" == "Bash" ]] || exit 0

# Only act on `flutter pub add` / `dart pub add`
if ! echo "$command_str" | grep -qE '(flutter|dart)\s+pub\s+add'; then
  exit 0
fi

# ── Extract the package name(s) ───────────────────────────────────────────────
# `flutter pub add pkg` or `flutter pub add pkg1 pkg2` or with version constraints
# e.g. `flutter pub add 'http:^1.0.0'` — strip version constraint for the lookup

packages=()
while IFS= read -r token; do
  # Skip flags (--dev, --sdk, etc.)
  [[ "$token" == --* ]] && continue
  # Strip version constraint (everything after ':' or '^' or '@')
  pkg=$(echo "$token" | sed 's/[:\^@].*//')
  [[ -n "$pkg" ]] && packages+=("$pkg")
done < <(echo "$command_str" \
  | sed -E 's/(flutter|dart)\s+pub\s+add\s*//' \
  | tr ' ' '\n' \
  | grep -v '^$')

[[ ${#packages[@]} -eq 0 ]] && exit 0

# ── Query pub.dev ─────────────────────────────────────────────────────────────

PUB_API="https://pub.dev/api/packages"
blocked=()
warnings=()

for pkg in "${packages[@]}"; do
  response=$(curl -sf --max-time 8 "${PUB_API}/${pkg}" 2>/dev/null || true)

  if [[ -z "$response" ]]; then
    warnings+=("  ⚠  '$pkg': could not reach pub.dev (proceeding anyway)")
    continue
  fi

  not_found=$(echo "$response" | jq -r '.error // empty')
  if [[ -n "$not_found" ]]; then
    blocked+=("  ✗  '$pkg': package not found on pub.dev")
    continue
  fi

  is_discontinued=$(echo "$response" | jq -r '.isDiscontinued // false')
  replaced_by=$(echo "$response" | jq -r '.replacedBy // empty')
  latest_version=$(echo "$response" | jq -r '.latest.version // "unknown"')
  published=$(echo "$response" | jq -r '.latest.published // empty')

  if [[ "$is_discontinued" == "true" ]]; then
    if [[ -n "$replaced_by" ]]; then
      blocked+=("  ✗  '$pkg' is discontinued. Official replacement: '$replaced_by'")
    else
      blocked+=("  ✗  '$pkg' is discontinued with no official replacement listed.")
    fi
    continue
  fi

  # Warn if the latest publish date is suspiciously old (> ~3 years)
  if [[ -n "$published" ]]; then
    pub_year=$(echo "$published" | cut -d'-' -f1)
    current_year=$(date +%Y)
    age=$(( current_year - pub_year ))
    if (( age >= 3 )); then
      warnings+=("  ⚠  '$pkg' (v${latest_version}): last published ${published:0:10} — consider checking for a maintained alternative")
    fi
  fi
done

# ── Report & decide ───────────────────────────────────────────────────────────

if [[ ${#warnings[@]} -gt 0 ]]; then
  echo "flutter-agent-tools: dependency warnings:"
  for w in "${warnings[@]}"; do echo "$w"; done
fi

if [[ ${#blocked[@]} -gt 0 ]]; then
  echo ""
  echo "flutter-agent-tools: blocking unsafe dependency addition:"
  for b in "${blocked[@]}"; do echo "$b"; done
  echo ""
  echo "Please use a current, non-discontinued package before proceeding."
  exit 1
fi

exit 0
