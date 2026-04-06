import 'diagnostics_node.dart';
import 'app_session.dart';

// When the Flutter framework chooses to elide multiple exceptions on stdout,
// you can infer this from `Flutter.Error` events; the `renderedErrorText` field
// will start with `'Another exception was thrown: '`.
//
// `errorsSinceReload` will also be non-zero (positive), but I don't know
// whether that's a cumulative error count or a duplicate count of this
// particular error.

/// Summarizes a [FlutterError] as a plain-text string suitable for
/// consumption by an MCP client or AI agent.
///
/// Two strategies are provided:
///
/// - [compactSummarizer]: the primary summarizer — error message, source
///   location, key render constraints, and stack call-site only. Used for
///   MCP log events.
/// - [detailedSummarizer]: includes hints and prose descriptions in addition
///   to the compact content. Intended for a future "explain this error"
///   tool where an agent explicitly requests more context.
typedef ErrorSummarizer = String Function(FlutterError error);

// ---------------------------------------------------------------------------
// Compact summarizer (primary)

/// The primary summarizer. Emits only:
/// - The specific error (`ErrorSummary`)
/// - Source location (`DiagnosticsBlock` + children)
/// - Offending widget constraints/size/direction + widget ID (`DiagnosticableTreeNode`)
/// - First stack frame (`DiagnosticsStackTrace`)
///
/// Omits hints and prose descriptions — on the assumption that an agent
/// already knows how to fix common errors given just the what and where.
/// The widget ID can be passed to `flutter_inspect_layout` for a deeper
/// drill-down without a separate tree traversal.
String compactSummarizer(FlutterError error) {
  final buf = StringBuffer();
  buf.writeln(error.detail);

  for (final prop in error.node.properties) {
    final type = prop.json['type'] as String? ?? '';
    switch (type) {
      case 'DiagnosticsBlock':
        final name = prop.name ?? '';
        if (name.isNotEmpty) buf.writeln('$name:');
        for (final child in prop.children) {
          final cdesc = child.description;
          if (cdesc.isNotEmpty) buf.writeln('  $cdesc');
        }

      case 'DiagnosticableTreeNode':
        final name = prop.name ?? '';
        final desc = prop.description;
        if (name.isNotEmpty) buf.write('$name: ');
        if (desc.isNotEmpty) buf.writeln(desc);
        for (final sub in prop.properties) {
          final sname = sub.name ?? '';
          final sdesc = sub.description;
          if (_renderSubProps.contains(sname) && sdesc.isNotEmpty) {
            buf.writeln('  $sname: $sdesc');
          }
        }
        if (prop.valueId != null) buf.writeln('  widget ID: ${prop.valueId}');

      case 'DiagnosticsStackTrace':
        final frame = prop.properties.firstOrNull;
        if (frame != null && frame.description.isNotEmpty) {
          buf.writeln('At: ${frame.description}');
        }
    }
  }

  return buf.toString().trim();
}

// ---------------------------------------------------------------------------
// Detailed summarizer

/// Includes everything in [compactSummarizer] plus error category, prose
/// descriptions, and hints. Intended for use when an agent explicitly requests
/// more context about an error — hints can suggest fixes for less-common
/// errors that an agent may not already know.
String detailedSummarizer(FlutterError error) {
  final buf = StringBuffer();

  // Category line.
  buf.writeln(error.description);

  // Specific error (ErrorSummary).
  final detail = error.detail;
  if (detail != error.description) buf.writeln(detail);

  for (final prop in error.node.properties) {
    _writeDetailedProperty(buf, prop);
  }

  return buf.toString().trim();
}

// Types we skip entirely.
const _skipTypes = {
  'ErrorSpacer',
  'DevToolsDeepLinkProperty',
  // Already surfaced via error.detail above.
  'ErrorSummary',
};

// Sub-properties of DiagnosticableTreeNode worth showing.
const _renderSubProps = {'constraints', 'size', 'direction'};

void _writeDetailedProperty(StringBuffer buf, DiagnosticsNode prop) {
  final type = prop.json['type'] as String? ?? '';
  if (_skipTypes.contains(type)) return;

  final desc = prop.description;
  if (desc.startsWith('◢◤')) return;

  switch (type) {
    case 'ErrorDescription':
      // Skip the intro "The following assertion was thrown..." line — the
      // category + summary already convey that. Keep all others.
      if (desc.startsWith('The following ')) return;
      if (desc.isNotEmpty) buf.writeln(desc);

    case 'ErrorHint':
      if (desc.isNotEmpty) buf.writeln('Hint: $desc');

    case 'DiagnosticsBlock':
      final name = prop.name ?? '';
      if (name.isNotEmpty) buf.writeln('$name:');
      for (final child in prop.children) {
        final cdesc = child.description;
        if (cdesc.isNotEmpty) buf.writeln('  $cdesc');
      }

    case 'DiagnosticableTreeNode':
      final name = prop.name ?? '';
      if (name.isNotEmpty) buf.write('$name: ');
      if (desc.isNotEmpty) buf.writeln(desc);
      for (final sub in prop.properties) {
        final sname = sub.name ?? '';
        final sdesc = sub.description;
        if (_renderSubProps.contains(sname) && sdesc.isNotEmpty) {
          buf.writeln('  $sname: $sdesc');
        }
      }
      if (prop.valueId != null) buf.writeln('  widget ID: ${prop.valueId}');

    case 'DiagnosticsStackTrace':
      // Show only the first user-code frame.
      final frame = prop.properties.firstOrNull;
      if (frame != null && frame.description.isNotEmpty) {
        buf.writeln('At: ${frame.description}');
      }

    default:
      // Named metadata (e.g. Handler, Recognizer).
      final name = prop.name ?? '';
      if (name.isNotEmpty && desc.isNotEmpty) {
        buf.writeln('$name: $desc');
      }
  }
}
