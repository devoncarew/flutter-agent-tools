#!/usr/bin/env node
'use strict';

// Cross-platform hook entry point for all supported coding agents.
// Performs fast-exit checks before invoking the Dart validation logic.
//
// Usage:
//   node scripts/deps_check.js --agent=claude  --mode=pub-add
//   node scripts/deps_check.js --agent=claude  --mode=pubspec-guard
//   node scripts/deps_check.js --agent=gemini  --mode=pub-add
//   node scripts/deps_check.js --agent=gemini  --mode=pubspec-guard
//   node scripts/deps_check.js --agent=copilot          (mode auto-detected)

const { spawnSync } = require('child_process');
const { readFileSync } = require('fs');
const path = require('path');

function getArg(name) {
  const prefix = `--${name}=`;
  const found = process.argv.find((a) => a.startsWith(prefix));
  return found ? found.slice(prefix.length) : null;
}

const agent = getArg('agent');
let mode = getArg('mode');

if (!agent) {
  process.stderr.write('deps_check: --agent=claude|copilot|gemini is required\n');
  process.exit(0); // Fail open.
}

// Read all of stdin upfront.
let rawInput;
try {
  rawInput = readFileSync(0, 'utf-8');
} catch (_) {
  process.exit(0);
}

// Copilot sends no --mode argument; detect it from the JSON content instead.
if (!mode) {
  if (agent === 'copilot') {
    if (rawInput.includes('"toolName":"bash"') && rawInput.includes('pub add')) {
      mode = 'pub-add';
    } else if (rawInput.includes('"toolName":"edit"') && rawInput.includes('pubspec.yaml')) {
      mode = 'pubspec-guard';
    } else {
      process.exit(0);
    }
  } else {
    process.stderr.write('deps_check: --mode=pub-add|pubspec-guard is required\n');
    process.exit(0); // Fail open.
  }
}

// Fast-exit: skip Dart invocation when there is nothing to check.
if (mode === 'pub-add' && !rawInput.includes('pub add')) process.exit(0);
if (mode === 'pubspec-guard' && !rawInput.includes('pubspec.yaml')) process.exit(0);

// Invoke the Dart validation logic.
const pluginRoot = path.resolve(__dirname, '..');
const result = spawnSync(
  'dart',
  ['run', 'bin/deps_check.dart', `--agent=${agent}`, `--mode=${mode}`],
  { cwd: pluginRoot, input: rawInput, encoding: 'utf8' },
);

if (result.stdout) process.stdout.write(result.stdout);
if (result.stderr) process.stderr.write(result.stderr);
process.exit(result.status ?? 0);
