# GitHub Copilot 'preToolUse' hook entry point for dependency health checks.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pluginRoot = Split-Path -Parent $scriptDir

$rawInput = [Console]::In.ReadToEnd()

# Detect mode from the hook input JSON (Copilot has no native matcher/if filtering).
if ($rawInput.Contains('"toolName":"bash"') -and $rawInput.Contains('pub add')) {
    $mode = 'pub-add'
} elseif ($rawInput.Contains('"toolName":"edit"') -and $rawInput.Contains('pubspec.yaml')) {
    $mode = 'pubspec-guard'
} else {
    exit 0
}

if (-not (Get-Command dart -ErrorAction SilentlyContinue)) { exit 0 }

Push-Location $pluginRoot
try {
    $rawInput | dart run bin/deps_check.dart --agent=copilot "--mode=$mode"
} finally {
    Pop-Location
}
exit 0
