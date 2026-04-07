import 'diagnostics_node.dart';

// Sub-properties to show for each child node.
const _childLayoutProps = {'parentData', 'constraints', 'size'};

/// Formats a [DiagnosticsNode] details subtree as a plain-text layout summary
/// suitable for consumption by an MCP client or AI agent.
///
/// The root node gets all its properties. Each child gets the key layout
/// properties: [parentData] (position + flex factor), [constraints] (what was
/// passed down), and [size] (what the child actually took). Children are
/// rendered recursively up to [maxDepth] levels below the root.
///
/// [maxChildren] Maximum number of children to list at each level before
/// truncating.
String formatLayoutDetails(
  DiagnosticsNode node, {
  int maxDepth = 4,
  int maxChildren = 20,
}) {
  final buf = StringBuffer();

  // Root: description + all named properties.
  buf.writeln(node.description);
  for (final prop in node.properties) {
    final name = prop.name ?? '';
    final desc = prop.description;
    if (name.isNotEmpty && desc.isNotEmpty) {
      buf.writeln('  $name: $desc');
    }
  }

  _writeChildren(
    buf,
    node.children,
    indent: 0,
    maxChildren: maxChildren,
    maxDepth: maxDepth,
    depth: 0,
  );

  return buf.toString().trim();
}

void _writeChildren(
  StringBuffer buf,
  List<DiagnosticsNode> children, {
  required int indent,
  required int maxChildren,
  required int maxDepth,
  required int depth,
}) {
  if (children.isEmpty || depth >= maxDepth) return;

  final pad = '  ' * indent;
  buf.writeln();
  buf.writeln('${pad}children (${children.length}):');

  final shown = children.take(maxChildren).toList();
  for (final child in shown) {
    final childName = child.name ?? '';
    buf.writeln(
      '$pad  ${childName.isNotEmpty ? "$childName: " : ""}${child.description}',
    );
    for (final prop in child.properties) {
      final name = prop.name ?? '';
      final desc = prop.description;
      if (_childLayoutProps.contains(name) && desc.isNotEmpty) {
        buf.writeln('$pad    $name: $desc');
      }
    }
    _writeChildren(
      buf,
      child.children,
      indent: indent + 2,
      maxChildren: maxChildren,
      maxDepth: maxDepth,
      depth: depth + 1,
    );
  }

  if (children.length > maxChildren) {
    buf.writeln('$pad  ... (${children.length - maxChildren} more children)');
  }
}
