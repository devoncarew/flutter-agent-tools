import 'diagnostics_node.dart';

/// Extracts navigator / route state from a [getRootWidgetTree] result and
/// formats it as plain text suitable for an MCP client or AI agent.
///
/// Traverses the widget tree to find all [Navigator] nodes, resolves the
/// locally-created screen widget for each route stack entry, and emits a
/// compact summary. The last entry in each navigator's stack is the current
/// (topmost) route.
///
/// Navigators whose entire route stack resolves to private widgets (names
/// starting with `_`) are suppressed — they are framework or shell-route
/// internals (e.g. go_router's `_AppShell`) that add noise without useful
/// orientation information.
///
/// If [currentPath] is provided (e.g. resolved from go_router via VM service
/// evaluate), it is included at the top of the output.
String formatRouteInfo(DiagnosticsNode root, {String? currentPath}) {
  final navigators = <_NavigatorInfo>[];
  _collectNavigators(root, 0, navigators);

  // Keep only navigators that have at least one publicly-named route entry.
  final visible =
      navigators
          .where(
            (n) =>
                n.routes.isNotEmpty &&
                n.routes.any((r) => !_isPrivateName(r.widgetType)),
          )
          .toList();

  if (visible.isEmpty) {
    if (navigators.isEmpty) {
      return 'No Navigator found in the widget tree.';
    }
    return 'Navigator found but route stack is empty.';
  }

  final buf = StringBuffer();
  if (currentPath != null) {
    buf.writeln('Current path: $currentPath');
    buf.writeln();
  }
  for (int ni = 0; ni < visible.length; ni++) {
    final nav = visible[ni];
    // Only show the navigator header when multiple navigators are visible —
    // nested navigator setups (e.g. shell routes) are the exception, not the rule.
    if (visible.length > 1) {
      buf.writeln('Navigator: ${nav.label}');
    }
    final count = nav.routes.length;
    buf.writeln('Route stack ($count ${count == 1 ? "entry" : "entries"}):');
    for (int i = 0; i < count; i++) {
      final route = nav.routes[i];
      final isCurrent = i == count - 1;
      final widgetName = route.widgetType ?? '(unknown)';
      final filePart =
          route.shortFile != null
              ? '  (${route.shortFile}${route.line != null ? ":${route.line}" : ""})'
              : '';
      final currentMarker = isCurrent ? '  ← current' : '';
      buf.writeln('  [${i + 1}/$count] $widgetName$filePart$currentMarker');
    }
    if (ni < visible.length - 1) buf.writeln();
  }

  return buf.toString().trim();
}

/// Returns all [DiagnosticsNode] instances in [root]'s subtree whose
/// [DiagnosticsNode.widgetRuntimeType] is `InheritedGoRouter`.
///
/// go_router places a single `InheritedGoRouter` near the top of the tree.
/// Its `notifier` field holds the [GoRouter] instance, which can be used (via
/// [FlutterServiceExtensions.evaluateOnObject]) to query the current route
/// configuration.
///
/// Returns an empty list if the app does not use go_router.
List<DiagnosticsNode> findGoRouterNodes(DiagnosticsNode root) {
  final result = <DiagnosticsNode>[];
  _collectGoRouterNodes(root, result);
  return result;
}

void _collectGoRouterNodes(DiagnosticsNode node, List<DiagnosticsNode> out) {
  if (node.widgetRuntimeType == 'InheritedGoRouter') {
    out.add(node);
    // Don't recurse further — nested GoRouters are not a go_router pattern.
    return;
  }
  for (final child in node.children) {
    _collectGoRouterNodes(child, out);
  }
}

// ---------------------------------------------------------------------------
// Internal data types

class _NavigatorInfo {
  _NavigatorInfo(this.description, this.depth, this.routes);

  final String description;
  final int depth;
  final List<_RouteEntry> routes;

  /// A short display label for this navigator (used when multiple are shown).
  String get label {
    // The go_router root navigator has "root" in its key description.
    if (description.contains(' root]')) return 'root navigator';
    return 'navigator';
  }
}

bool _isPrivateName(String? name) => name != null && name.startsWith('_');

class _RouteEntry {
  _RouteEntry({this.widgetType, this.shortFile, this.line});

  final String? widgetType;
  final String? shortFile;
  final int? line;
}

// ---------------------------------------------------------------------------
// Tree traversal

void _collectNavigators(
  DiagnosticsNode node,
  int depth,
  List<_NavigatorInfo> out,
) {
  if (_isNavigator(node)) {
    final routes = <_RouteEntry>[];
    for (final child in node.children) {
      final local = _firstLocalWidget(child);
      if (local != null) {
        final loc = local.json['creationLocation'] as Map<String, dynamic>?;
        routes.add(
          _RouteEntry(
            widgetType: local.widgetRuntimeType ?? local.description,
            shortFile: _shortFilePath(loc?['file'] as String?),
            line: loc?['line'] as int?,
          ),
        );
      } else {
        // No local widget found — include as an unresolved entry.
        routes.add(_RouteEntry(widgetType: child.widgetRuntimeType));
      }
    }
    out.add(_NavigatorInfo(node.description, depth, routes));
  }

  for (final child in node.children) {
    _collectNavigators(child, depth + 1, out);
  }
}

bool _isNavigator(DiagnosticsNode node) {
  return node.widgetRuntimeType == 'Navigator' ||
      node.description.startsWith('Navigator-[');
}

/// Returns the first descendant (including [node] itself) whose
/// `creationLocation.file` is not inside `.pub-cache`, i.e. a widget defined
/// in the local project (or a direct dependency vendored into the project).
///
/// `createdByLocalProject` is unreliable — go_router's `Builder` wrapper
/// carries that flag even though it lives in pub-cache. Checking the file
/// path is more accurate.
DiagnosticsNode? _firstLocalWidget(DiagnosticsNode node) {
  final loc = node.json['creationLocation'] as Map<String, dynamic>?;
  final file = loc?['file'] as String?;
  if (file != null && !file.contains('/.pub-cache/')) return node;
  for (final child in node.children) {
    final found = _firstLocalWidget(child);
    if (found != null) return found;
  }
  return null;
}

/// Returns a short, human-readable file path from a `file://` URI.
///
/// For project files (under `lib/`), returns the path from `lib/` onward.
/// For pub-cache files, returns `[pub-cache]`.
/// Falls back to the last two path segments.
String? _shortFilePath(String? fileUri) {
  if (fileUri == null) return null;
  final path = fileUri.startsWith('file://') ? fileUri.substring(7) : fileUri;
  if (path.contains('/.pub-cache/')) return null; // not useful to surface
  final libIdx = path.indexOf('/lib/');
  if (libIdx >= 0) return path.substring(libIdx + 1);
  final parts = path.split('/');
  return parts.length >= 2 ? parts.sublist(parts.length - 2).join('/') : path;
}
