import 'diagnostics_node.dart';

// Sub-properties to show for each child node.
const _childLayoutProps = {'parentData', 'constraints', 'size'};

/// Formats a [DiagnosticsNode] details subtree as a plain-text layout summary
/// suitable for consumption by an MCP client or AI agent.
///
/// The root node gets all its properties. Each child gets the key layout
/// properties: [parentData] (position + flex factor), [constraints] (what was
/// passed down), and [size] (what the child actually took).
///
/// [maxChildren] Maximum number of children to list before truncating.
String formatLayoutDetails(DiagnosticsNode node, {int maxChildren = 20}) {
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

  // Children: key layout properties only.
  final children = node.children;
  if (children.isNotEmpty) {
    buf.writeln();
    buf.writeln('children (${children.length}):');
    final shown = children.take(maxChildren).toList();
    for (final child in shown) {
      final childName = child.name ?? '';
      buf.writeln(
        '  ${childName.isNotEmpty ? "$childName: " : ""}${child.description}',
      );
      for (final prop in child.properties) {
        final name = prop.name ?? '';
        final desc = prop.description;
        if (_childLayoutProps.contains(name) && desc.isNotEmpty) {
          buf.writeln('    $name: $desc');
        }
      }
    }
    if (children.length > maxChildren) {
      buf.writeln('  ... (${children.length - maxChildren} more children)');
    }
  }

  return buf.toString().trim();
}
