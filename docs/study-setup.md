## Setup

- flutter create --platforms=android,ios,macos,web showcase
- cd showcase
- flutter run -d macos
- `rm test/*_test.dart`
- claude --plugin-dir /Users/.../flutter-agent-tools

## .claude/settings.local.json:

```
{
  "permissions": {
    "allow": [
      "Bash(flutter pub:*)",
      "mcp__plugin_flutter-slipstream_packages__package_summary",
      "mcp__plugin_flutter-slipstream_packages__library_stub",
      "mcp__plugin_flutter-slipstream_packages__class_stub",
      "mcp__plugin_flutter-slipstream_inspector__run_app",
      "mcp__plugin_flutter-slipstream_inspector__take_screenshot",
      "mcp__plugin_flutter-slipstream_inspector__navigate",
      "mcp__plugin_flutter-slipstream_inspector__reload",
      "mcp__plugin_flutter-slipstream_inspector__tap",
      "mcp__plugin_flutter-slipstream_inspector__get_semantics",
      "mcp__plugin_flutter-slipstream_inspector__close_app"
    ]
  }
}
```

## Prompt

Hi! We're testing out a new Claude plugin, with two MCP servers, 'inspector' and
'packages'. The plugin is flutter-slipstream: "A Claude Code plugin that makes
AI coding agents more effective for Dart and Flutter projects.".

Your job is to test the plugin - learn what it does well and where it could
improve - and provide feedback about the tool. Please familiarize yourself with
its MCP tools. In order to test it you'll be building an app. This directory is
populated with a standard hello-world flutter app. Please - working
iteratively - turn it into a Flutter widget showcase. Try and use popular and
common packages, like provider and go_router. Feel free to use packages you're
less familiar with, in order to test out the tool's features. Building the app
is a mechanism for testing this Claude plugin.

Relatively early in your work, please start the app. Then work iteratively, hot
reloading at regular intervals. If you get stuck please ask questions. Otherwise
work independently. Once you're done, please write your feedback - pros, cons,
bugs, and things which could improve the tool - as well as a work log - to
/Users/.../flutter-agent-tools/docs/feedback-xx.md.

Do you have any questions before you begin?

## Gemini

Hi! We're testing out new coding agent tooling in the form of two MCP servers,
'slipstream-inspector' and 'slipstream-packages'. The general tool is Flutter
Slipstream: "A tool that makes AI coding agents more effective for Dart and
Flutter projects.".

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
- Use a bottom navigation bar.
- In one page of the navigation bar include a very small widget showcase.
- In another, include a Mondrian art page.
- In another, include a small game (tic tac toe? something else?).

Building the app is a mechanism for testing this tool. You can assume a mobile
phone target / mobile phone screen dimensions.

Relatively early in your work, please start the app. Then - work iteratively -
hot reload at regular intervals. You should work independently; if you get stuck
skip the section you're working on. Once you're done, please write your
feedback - pros, cons, bugs, and things which could improve the tool - as well
as a work log - to 'feedback.md' in the current directory.

Do you have any questions before you begin?
