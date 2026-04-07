import 'dart:convert';

/// Formats the JSON output of `getSemanticsTree()` as a human-readable
/// semantics summary.
///
/// The input is a flat JSON array of tuples:
/// ```
/// [[id, role, label, value, hint, checked, toggled, selected, enabled,
///   focused, actions, left, top, right, bottom], ...]
/// ```
///
/// Output:
/// ```
/// [button]     Sign in
/// [textfield]  Email address
/// [checkbox]   Remember me (checked)
/// [text]       Hello, world
/// ```
String formatSemanticsTree(String json) {
  if (json.startsWith('error:')) {
    return json;
  }

  final List<dynamic> raw;
  try {
    raw = jsonDecode(json) as List<dynamic>;
  } catch (e) {
    return 'error: could not parse semantics tree: $e';
  }

  final nodes = raw.map((e) => _SemNode.fromTuple(e as List<dynamic>)).toList();
  final visible = nodes.where((n) => n.hasContent).toList();

  if (visible.isEmpty) return 'No visible text or interactive elements found.';

  final buf = StringBuffer();
  for (final n in visible) {
    buf.writeln(n.format());
  }
  return buf.toString().trim();
}

// ---------------------------------------------------------------------------
// Internal model

class _SemNode {
  _SemNode({
    required this.id,
    required this.role,
    required this.label,
    required this.value,
    required this.hint,
    required this.checked,
    required this.toggled,
    required this.focused,
  });

  factory _SemNode.fromTuple(List<dynamic> t) {
    return _SemNode(
      id: t[0] as int,
      role: t[1] as String,
      label: t[2] as String,
      value: t[3] as String,
      hint: t[4] as String,
      checked: t[5] as bool?,
      toggled: t[6] as bool?,
      focused: t[9] as bool,
    );
  }

  final int id;
  final String role;
  final String label;
  final String value;
  final String hint;
  final bool? checked;
  final bool? toggled;
  final bool focused;

  /// Whether this node has any user-visible content worth surfacing.
  bool get hasContent =>
      label.isNotEmpty ||
      value.isNotEmpty ||
      hint.isNotEmpty ||
      role.isNotEmpty;

  String format() {
    final displayRole = role.isNotEmpty ? role : 'text';
    final pad = ' ' * (12 - displayRole.length).clamp(0, 12);

    // Primary display text: prefer label, then value, then hint.
    final text =
        label.isNotEmpty
            ? label
            : value.isNotEmpty
            ? value
            : hint;

    final details = <String>[];
    if (value.isNotEmpty && label.isNotEmpty) details.add('value: $value');
    if (hint.isNotEmpty) details.add('hint: $hint');
    if (checked == true) details.add('checked');
    if (checked == false) details.add('unchecked');
    if (toggled == true) details.add('on');
    if (toggled == false) details.add('off');
    if (focused) details.add('focused');

    final suffix = details.isNotEmpty ? ' (${details.join(', ')})' : '';
    return '[$displayRole]$pad$text$suffix';
  }
}
