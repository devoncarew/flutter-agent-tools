## Setup

- flutter create --platforms=android,ios,macos,web showcase
- cd showcase
- `rm test/*_test.dart`
- flutter run -d macos
- claude --plugin-dir /Users/.../flutter-agent-tools

## .claude/settings.local.json

```
{
  "permissions": {
    "allow": [
      "Bash(dart *)",
      "Bash(flutter *)",
      "Edit",
      "Write",
      "mcp__plugin_flutter-slipstream_packages__package_summary",
      "mcp__plugin_flutter-slipstream_packages__class_stub",
      "mcp__plugin_flutter-slipstream_inspector__run_app",
      "mcp__plugin_flutter-slipstream_inspector__get_output",
      "mcp__plugin_flutter-slipstream_inspector__take_screenshot",
      "mcp__plugin_flutter-slipstream_inspector__perform_set_text",
      "mcp__plugin_flutter-slipstream_inspector__perform_tap",
      "mcp__plugin_flutter-slipstream_inspector__navigate",
      "mcp__plugin_flutter-slipstream_inspector__perform_scroll_until_visible",
      "mcp__plugin_flutter-slipstream_inspector__perform_scroll",
      "mcp__plugin_flutter-slipstream_inspector__reload",
      "mcp__plugin_flutter-slipstream_inspector__perform_semantic_action",
      "mcp__plugin_flutter-slipstream_inspector__get_semantics",
      "mcp__plugin_flutter-slipstream_inspector__get_route",
      "mcp__plugin_flutter-slipstream_inspector__close_app"
    ]
  }
}
```

## Claude Prompt

TODO: This tends to just write everything and then run the tool after. We should
switch to having separate, sequential min-prompts per page.

Hi! We're testing out a new Claude plugin; it has two MCP servers, 'inspector'
and 'packages'. The plugin is flutter-slipstream: "A tool that makes AI coding
agents more effective for Dart and Flutter projects".

Your job is to put the plugin through its paces — learn what it does well and
where it could improve — and provide feedback about it. Please familiarize
yourself with its MCP tools before starting. In order to test it you'll be
building an app. This directory is populated with a standard hello-world Flutter
app. Please — working iteratively — turn it into a small Flutter widget
showcase. You can assume a mobile phone sized screen.

App requirements:

- Scaffold with a drawer and a bottom navigation bar (3 or 4 tabs)
- theme toggle in the app bar (light/dark)
- each tab should demo a few Flutter widgets — include at minimum a text input
  field, a scrollable list, and a form with a button
- use `provider` for state management (theme toggle is fine)
- use `go_router` for navigation
- add `slipstream_agent` as a dependency and initialize it in main — this
  unlocks companion-mode tooling in the inspector

How to work:

- start the app relatively early (via the inspector's `run_app`)
- hot reload as you go; after each reload or interaction, check `get_output` for
  errors and app output
- take screenshots to verify visual changes; don't assume edits worked
- to interact with the running app, prefer the finder-based tools
  (`perform_tap`, `perform_set_text`, `perform_scroll`)
- use the `packages` MCP server to learn the API of any unfamiliar package
- work independently; if you get stuck, skip the section you're working on

Once done, please write your feedback — pros, cons, bugs, and areas for
improvement, along with a brief work log — to a `feedback.md` document in this
directory. Building the app is a mechanism for testing the plugin, not the end
goal.

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
