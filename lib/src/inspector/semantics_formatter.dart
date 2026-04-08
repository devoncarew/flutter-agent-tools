import 'semantic_node.dart';

/// Formats a list of [SemanticNode]s as a human-readable semantics summary.
///
/// Output format:
/// ```
/// [button id=16 selected action:tap]
///   label: "Playlist Tab 1 of 4"
///   size: 97.5x80
/// [button id=12]
///   size: 48x36.5
/// ```
///
/// State flags (checked, selected, etc.) and supported actions appear on the
/// header line. Labels longer than 100 characters are truncated with `…`.
/// Node position is omitted — coordinates are in local space and unreliable
/// without accumulating parent transforms.
String formatSemanticsTree(List<SemanticNode> nodes) {
  final visible = nodes.where(_hasContent).toList();
  if (visible.isEmpty) {
    return 'No visible text or interactive elements found.';
  }
  return visible.map((node) => _formatNode(node)).join('');
}

String _formatNode(SemanticNode node) {
  final buf = StringBuffer();

  // State flags on the header line.
  final states = <String>[];
  if (node.checked == true) states.add('checked');
  if (node.checked == false) states.add('unchecked');
  if (node.toggled == true) states.add('on');
  if (node.toggled == false) states.add('off');
  if (node.selected == true) states.add('selected');
  if (node.enabled == false) states.add('disabled');
  if (node.focused) states.add('focused');
  final statesStr = states.isEmpty ? '' : ' ${states.join(' ')}';

  // Supported actions on the header line.
  final actionsStr = node.describeActions.map((a) => ' action:$a').join('');

  final role = node.role.isNotEmpty ? node.role : 'text';
  buf.writeln('[$role id=${node.id}$statesStr$actionsStr]');

  if (node.label.isNotEmpty) buf.writeln('  label: "${_trunc(node.label)}"');
  if (node.hint.isNotEmpty) buf.writeln('  hint: ${node.hint}');
  if (node.value.isNotEmpty) buf.writeln('  value: ${_trunc(node.value)}');

  // Size only — position is in local coordinate space, not screen space.
  final width = node.right - node.left;
  final height = node.bottom - node.top;
  buf.writeln('  size: ${_fmt(width)}x${_fmt(height)}');

  return buf.toString();
}

String _trunc(String s, [int max = 100]) =>
    s.length > max ? '${s.substring(0, max - 1)}…' : s;

String _fmt(double val) =>
    val.toStringAsFixed(1).replaceFirst(_stripTrailingZeros, '');

final RegExp _stripTrailingZeros = RegExp(r'\.?0+$');

bool _hasContent(SemanticNode node) =>
    node.label.isNotEmpty ||
    node.value.isNotEmpty ||
    node.hint.isNotEmpty ||
    node.role.isNotEmpty;
