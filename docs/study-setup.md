## Setup

- flutter create --platforms=android,ios,macos,web showcase
- cd showcase
- `rm test/*_test.dart`
- flutter run -d macos
- claude --plugin-dir /Users/.../flutter-agent-tools

## .claude/settings.local.json:

```
{
  "permissions": {
    "allow": [
      "Bash(dart *)",
      "Bash(flutter *)",
      "mcp__plugin_flutter-slipstream_*"
    ]
  }
}
```

## Claude Prompt

Hi! We're testing out a new Claude plugin; is has two MCP servers, 'inspector'
and 'packages'. The plugin is flutter-slipstream: "A tool to make AI coding
agents more effective for Dart and Flutter projects".

Your job is to put the plugin through it's paces - learn what it does well and
where it could improve - and provide feedback about it. Please familiarize
yourself with its MCP tools. In order to test it you'll be building an app. This
directory is populated with a standard hello-world flutter app. Please - working
iteratively - turn it into a Flutter widget showcase.

- relatively early in your work, please start the app
- work iteratively, hot reloading at regular intervals
- work independently; if you get stuck skip the section you're working on
- use packages like provider and go_router
- use a Scaffold with a drawer and a bottom navigation bar
- include a theme toggle in the app bar
- each page in the bottom navigation bar should demo a few flutter widgets

Once done, please write your feedback - pros, cons, bugs, areas for improvement,
as well as a work log. to a feedback.md document. Building this app is a
mechanism for testing the plugin.

Do you have any questions before you begin?

## Gemini Prompt

Hi! We're testing out new coding agent tooling in the form of two MCP servers,
'inspector' and 'packages'. The general tool is Flutter Slipstream /
flutter-slipstream: "A tool that makes AI coding agents more effective for Dart
and Flutter projects.".

Your job is to test the tool - learn what it does well and where it could
improve - and provide feedback about it. Please familiarize yourself with its
MCP tools. In order to test it you'll be building an app. This directory is
populated with a standard hello-world Flutter app. Please - working
iteratively - turn it into a working Flutter app.

- Try and use popular and common packages, like provider and go_router.
- Feel free to use packages you're less familiar with, in order to test out the
  tool's features.
- Have a theme toggle.
- Use a Scaffold and a drawer.
- Use a bottom navigation bar with several pages.
- For each page, have a set of components that together form a very small widget
  showcase.

Building the app is a mechanism for testing this tool. You can assume a mobile
phone target / mobile phone screen dimensions.

Relatively early in your work, please start the app. Then - work iteratively -
hot reload at regular intervals. You should work independently; if you get stuck
skip the section you're working on. Once you're done, please write your
feedback - pros, cons, bugs, and things which could improve the tool - as well
as a work log - to 'feedback.md' in the current directory.

Do you have any questions before you begin?

## Gemini Smoke test

Hi! We're testing out new coding agent tooling in the form of two MCP servers,
'inspector' and 'packages'. The general tool is Flutter Slipstream /
flutter-slipstream: "A tool that makes AI coding agents more effective for Dart
and Flutter projects.".

Your job is to smoke test the tool - to use tools from each MCP server in a
roughly typical workflow for developers. We want to catch any broad regressions
in the tool as well as any minor issues or usability rough spots. You can use
the app in the current directory as part of your testing.

Early in your work please start the app. You should work independently; if you
get stuck skip the section you're working on. Once you're done, please write
your feedback - pros, cons, bugs, and things which could improve the tool - as
well as a work log - to 'feedback.md' in the current directory.

Do you have any questions before you begin?
