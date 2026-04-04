/// A simplified representation of a Flutter [DiagnosticsNode] as returned
/// by Flutter inspector VM service extensions.
///
/// The Flutter framework's DiagnosticsNode is a rich class with many
/// subclasses and rendering concerns. This class captures only the fields
/// relevant to reading and navigating the diagnostic tree over the wire.
///
/// Two response shapes exist depending on the call:
/// - Full-detail responses (e.g. [FlutterServiceExtensions.getRootWidget])
///   include [type], [level], [style], [properties], and [valueId].
/// - Summary/iterative responses (e.g. [FlutterServiceExtensions.getRootWidgetTree])
///   include [widgetRuntimeType] and [shouldIndent], but fewer property fields.
///
/// The raw [json] map is preserved for accessing any fields not modelled here.
class DiagnosticsNode {
  DiagnosticsNode({
    required this.description,
    this.name,
    this.type,
    this.widgetRuntimeType,
    this.level,
    this.style,
    this.value,
    this.valueId,
    this.hasChildren = false,
    this.truncated = false,
    this.shouldIndent = true,
    required this.properties,
    required this.children,
    required this.json,
  });

  factory DiagnosticsNode.fromJson(Map<String, dynamic> json) {
    return DiagnosticsNode(
      description: json['description'] as String? ?? '',
      name: json['name'] as String?,
      type: json['type'] as String?,
      widgetRuntimeType: json['widgetRuntimeType'] as String?,
      level: json['level'] as String?,
      style: json['style'] as String?,
      value: json['value'],
      valueId: json['valueId'] as String?,
      hasChildren: json['hasChildren'] as bool? ?? false,
      truncated: json['truncated'] as bool? ?? false,
      shouldIndent: json['shouldIndent'] as bool? ?? true,
      properties:
          (json['properties'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(DiagnosticsNode.fromJson)
              .toList() ??
          const [],
      children:
          (json['children'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(DiagnosticsNode.fromJson)
              .toList() ??
          const [],
      json: json,
    );
  }

  /// Human-readable description of this node (always present).
  final String description;

  /// The property name, if this node is a named property of its parent.
  final String? name;

  /// The Dart runtime type name. Present in full-detail responses.
  final String? type;

  /// The widget class name. Present in summary tree responses.
  final String? widgetRuntimeType;

  /// Diagnostic level: 'hidden', 'fine', 'debug', 'info', 'warning', 'hint',
  /// 'summary', 'error', or 'off'. Omitted when 'info' (the default).
  final String? level;

  /// Tree display style hint: 'sparse', 'dense', 'flat', 'error', etc.
  /// Omitted when 'sparse' (the default).
  final String? style;

  /// The property value for leaf property nodes (String, num, bool, or null).
  final Object? value;

  /// Inspector object handle for this node. Used to identify the object in
  /// subsequent inspector calls such as [FlutterServiceExtensions.screenshot].
  /// Present in full-detail responses.
  final String? valueId;

  /// Whether this node has children that were not included in this response
  /// (i.e. the subtree was not fetched deep enough).
  final bool hasChildren;

  /// Whether this node's child list was truncated due to length limits.
  final bool truncated;

  /// Display hint: whether this node's children should be indented.
  /// False for flat/error styles.
  final bool shouldIndent;

  /// Property nodes describing this node's attributes.
  final List<DiagnosticsNode> properties;

  /// Child nodes in the widget/render tree.
  final List<DiagnosticsNode> children;

  /// The raw JSON map from the wire, for accessing fields not modelled above.
  final Map<String, dynamic> json;
}
