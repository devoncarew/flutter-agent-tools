import 'dart:convert';

/// A single node from the Flutter semantics tree, as returned by
/// [parseSemanticsTree].
///
/// The flat list produced by [parseSemanticsTree] is already filtered: hidden,
/// invisible, and merged-into-parent nodes are excluded. Ordering is
/// depth-first (top of screen to bottom, roughly).
class SemanticNode {
  const SemanticNode({
    required this.id,
    required this.role,
    required this.label,
    required this.value,
    required this.hint,
    required this.checked,
    required this.toggled,
    required this.selected,
    required this.enabled,
    required this.focused,
    required this.actions,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Framework-internal integer ID. Root node is always 0.
  /// Directly usable as `SemanticsActionEvent.nodeId` — no conversion needed.
  final int id;

  /// Role derived from the node's flags: 'button', 'textfield', 'slider',
  /// 'link', 'image', 'header', 'checkbox', 'toggle', 'radio', or '' for
  /// plain text/containers.
  final String role;

  /// Primary accessibility label.
  final String label;

  /// Current value (e.g. slider position, text field content).
  final String value;

  /// Short description of what happens on action.
  final String hint;

  /// Checked state for checkboxes. `null` if the concept does not apply.
  final bool? checked;

  /// Toggled state for switches. `null` if the concept does not apply.
  final bool? toggled;

  /// Selected state (tabs, list items). `null` if the concept does not apply.
  final bool? selected;

  /// Enabled/disabled state. `null` if the concept does not apply.
  final bool? enabled;

  /// Whether this node currently has input focus.
  final bool focused;

  /// `SemanticsAction` bitmask from `dart:ui`. Common bits:
  ///
  /// - tap=1
  /// - longPress=2
  /// - scrollLeft=4
  /// - scrollRight=8
  /// - scrollUp=16
  /// - scrollDown=32
  /// - increase=64
  /// - decrease=128
  /// - setText=1<<21
  /// - focus=1<<22.
  final int actions;

  /// Bounding box in the node's local coordinate space.
  /// The root node's local space is screen coordinates.
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Whether the node supports a tap action.
  bool get supportsTap => actions & 1 != 0;

  List<String> get describeActions {
    if (actions == 0) return const [];

    final result = <String>[];

    if ((actions & 1) != 0) result.add('tap');
    if ((actions & 2) != 0) result.add('longPress');
    if ((actions & 4) != 0) result.add('scrollLeft');
    if ((actions & 8) != 0) result.add('scrollRight');
    if ((actions & 16) != 0) result.add('scrollUp');
    if ((actions & 32) != 0) result.add('scrollDown');
    if ((actions & 64) != 0) result.add('increase');
    if ((actions & 128) != 0) result.add('decrease');
    if ((actions & (1 << 21)) != 0) result.add('setText');
    if ((actions & (1 << 22)) != 0) result.add('focus');

    return result;
  }
}

/// Parses the raw JSON output of `getSemanticsTreeJson()` into a flat list of
/// [SemanticNode]s.
///
/// The JSON is a flat array of tuples:
/// ```
/// [[id, role, label, value, hint, checked, toggled, selected, enabled,
///   focused, actions, left, top, right, bottom], ...]
/// ```
///
/// Returns an empty list if [json] is an empty array. Throws a [FormatException]
/// if [json] is malformed.
///
/// Error strings (beginning with `"error:"`) are not valid input — callers
/// should check for that prefix before calling this function.
List<SemanticNode> parseSemanticsTree(String json) {
  final List<dynamic> raw = jsonDecode(json) as List<dynamic>;
  return raw.map((e) => _nodeFromTuple(e as List<dynamic>)).toList();
}

SemanticNode _nodeFromTuple(List<dynamic> t) {
  return SemanticNode(
    id: t[0] as int,
    role: t[1] as String,
    label: t[2] as String,
    value: t[3] as String,
    hint: t[4] as String,
    checked: t[5] as bool?,
    toggled: t[6] as bool?,
    selected: t[7] as bool?,
    enabled: t[8] as bool?,
    focused: t[9] as bool,
    actions: t[10] as int,
    left: (t[11] as num).toDouble(),
    top: (t[12] as num).toDouble(),
    right: (t[13] as num).toDouble(),
    bottom: (t[14] as num).toDouble(),
  );
}
