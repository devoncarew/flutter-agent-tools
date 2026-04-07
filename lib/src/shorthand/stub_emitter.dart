import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Emits a Dart stub file for [library]: public API surface only, with method
/// bodies removed. Private declarations, `@internal` members, and implicit
/// default constructors are omitted.
///
/// Mixin-contributed methods are inlined into the class body with an
/// attribution comment `// from MixinName`.
String emitLibraryStub(LibraryElement library) {
  final buf = StringBuffer();
  final ns = library.exportNamespace.definedNames2;

  // Collect top-level elements from the export namespace, deduped by name.
  final classes = <InterfaceElement>[];
  final mixins = <MixinElement>[];
  final extensions = <ExtensionElement>[];
  final enums = <EnumElement>[];
  final functions = <TopLevelFunctionElement>[];
  final variables = <TopLevelVariableElement>[];
  final typedefs = <TypeAliasElement>[];

  // Track variable names added via GetterElement to avoid duplicates if both
  // a getter and setter appear in the namespace.
  final seenVariableNames = <String>{};

  for (final entry in ns.entries) {
    if (entry.key.startsWith('_')) continue;
    switch (entry.value) {
      case EnumElement e:
        enums.add(e);
      case MixinElement e:
        mixins.add(e);
      case ClassElement e:
        classes.add(e);
      case ExtensionElement e:
        extensions.add(e);
      case TopLevelFunctionElement e:
        functions.add(e);
      case TypeAliasElement e:
        typedefs.add(e);
      // Top-level variables are exposed in the namespace as GetterElements
      // (and SetterElements for non-final vars). Reach through to the variable.
      case GetterElement e when e.isOriginVariable:
        final v = e.variable;
        if (v is TopLevelVariableElement && seenVariableNames.add(v.name!)) {
          variables.add(v);
        }
    }
  }

  // Sort everything alphabetically for stable output.
  classes.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
  mixins.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
  extensions.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
  enums.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
  functions.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
  variables.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
  typedefs.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

  bool needsBlank = false;
  void blank() {
    if (needsBlank) buf.writeln();
    needsBlank = false;
  }

  for (final e in typedefs) {
    blank();
    _emitTypeAlias(buf, e);
    needsBlank = true;
  }
  for (final e in enums) {
    blank();
    _emitEnum(buf, e);
    needsBlank = true;
  }
  for (final e in classes) {
    blank();
    _emitInterface(buf, e);
    needsBlank = true;
  }
  for (final e in mixins) {
    blank();
    _emitInterface(buf, e);
    needsBlank = true;
  }
  for (final e in extensions) {
    blank();
    _emitExtension(buf, e);
    needsBlank = true;
  }
  for (final e in functions) {
    blank();
    _emitDocComment(buf, e.documentationComment);
    buf.writeln('${_typeName(e.returnType)} ${e.name}${_params(e)};');
    needsBlank = true;
  }
  for (final e in variables) {
    blank();
    _emitDocComment(buf, e.documentationComment);
    final mod = e.isConst ? 'const' : (e.isFinal ? 'final' : '');
    buf.writeln(
      '${mod.isEmpty ? '' : '$mod '}'
      '${_typeName(e.type)} ${e.name};',
    );
    needsBlank = true;
  }

  return buf.toString();
}

// ---------------------------------------------------------------------------
// Interface types (class, mixin, abstract class)

void _emitInterface(StringBuffer buf, InstanceElement e) {
  _emitDocComment(buf, e.firstFragment.documentationComment);

  // Keyword + name + type params.
  final keyword = switch (e) {
    MixinElement() => 'mixin',
    ClassElement(isSealed: true) => 'sealed class',
    ClassElement(isAbstract: true, isInterface: true) =>
      'abstract interface class',
    ClassElement(isAbstract: true) => 'abstract class',
    ClassElement(isInterface: true) => 'interface class',
    ClassElement(isFinal: true) => 'final class',
    _ => 'class',
  };
  buf.write('$keyword ${e.name}${_typeParams(e.typeParameters)}');

  if (e is MixinElement) {
    // superclassConstraints always contains Object when there is no explicit
    // `on` clause — filter it out so we only emit real constraints.
    final constraints =
        e.superclassConstraints
            .where((t) => t.element.name != 'Object')
            .toList();
    if (constraints.isNotEmpty) {
      buf.write(' on ${constraints.map(_typeName).join(', ')}');
    }
    if (e.interfaces.isNotEmpty) {
      buf.write(' implements ${e.interfaces.map(_typeName).join(', ')}');
    }
  } else if (e is InterfaceElement) {
    if (e.supertype != null &&
        e.supertype!.element.name != 'Object' &&
        e.supertype!.element.name != null) {
      buf.write(' extends ${_typeName(e.supertype!)}');
    }
    if (e.mixins.isNotEmpty) {
      buf.write(' with ${e.mixins.map(_typeName).join(', ')}');
    }
    if (e.interfaces.isNotEmpty) {
      buf.write(' implements ${e.interfaces.map(_typeName).join(', ')}');
    }
  }

  buf.writeln(' {');

  // Constructors (skip implicit default).
  if (e is InterfaceElement) {
    for (final c in e.constructors) {
      if (c.isPrivate) continue;
      if (c.isOriginImplicitDefault) continue;
      _emitDocComment(buf, c.documentationComment, indent: '  ');
      buf.writeln('  ${_constructor(e, c)};');
    }
  }

  // Fields (skip those induced by explicit getters/setters).
  for (final f in e.fields) {
    if (f.isPrivate || !f.isOriginDeclaration) continue;
    _emitDocComment(buf, f.documentationComment, indent: '  ');
    final mods = [
      if (f.isStatic) 'static',
      if (f.isConst) 'const' else if (f.isFinal) 'final',
    ].join(' ');
    buf.writeln(
      '  ${mods.isEmpty ? '' : '$mods '}${_typeName(f.type)} ${f.name};',
    );
  }

  // Methods declared directly on this element.
  final directMethodNames = {
    for (final m in e.methods)
      if (!m.isPrivate) m.name ?? '',
  };
  for (final m in e.methods) {
    if (m.isPrivate) continue;
    _emitDocComment(buf, m.documentationComment, indent: '  ');
    _emitMethod(buf, m);
  }

  // Mixin-contributed methods, inlined with attribution.
  if (e is InterfaceElement) {
    for (final mixinType in e.mixins) {
      final mixin = mixinType.element;
      for (final m in mixin.methods) {
        if (m.isPrivate) continue;
        // Skip if overridden by a direct method.
        if (directMethodNames.contains(m.name)) continue;
        _emitDocComment(buf, m.documentationComment, indent: '  ');
        buf.writeln('  // from ${mixin.name}');
        _emitMethod(buf, m);
      }
    }
  }

  // Explicit getters/setters (not induced by field declarations).
  for (final a in e.getters) {
    if (a.isPrivate || !a.isOriginDeclaration) continue;
    _emitDocComment(buf, a.documentationComment, indent: '  ');
    buf.writeln(
      '  ${a.isStatic ? 'static ' : ''}${_typeName(a.returnType)} get ${a.name};',
    );
  }
  for (final a in e.setters) {
    if (a.isPrivate || !a.isOriginDeclaration) continue;
    _emitDocComment(buf, a.documentationComment, indent: '  ');
    buf.writeln(
      '  ${a.isStatic ? 'static ' : ''}set ${a.name}(${_typeName(a.formalParameters.first.type)} value);',
    );
  }

  buf.writeln('}');
}

// ---------------------------------------------------------------------------
// Extension

void _emitExtension(StringBuffer buf, ExtensionElement e) {
  _emitDocComment(buf, e.firstFragment.documentationComment);
  final name = e.name ?? '';
  final on = _typeName(e.extendedType);
  buf.writeln('extension ${name.isEmpty ? '' : '$name '}on $on {');

  for (final m in e.methods) {
    if (m.isPrivate) continue;
    _emitDocComment(buf, m.documentationComment, indent: '  ');
    _emitMethod(buf, m);
  }
  for (final a in e.getters) {
    if (a.isPrivate || !a.isOriginDeclaration) continue;
    _emitDocComment(buf, a.documentationComment, indent: '  ');
    buf.writeln('  ${_typeName(a.returnType)} get ${a.name};');
  }
  for (final a in e.setters) {
    if (a.isPrivate || !a.isOriginDeclaration) continue;
    _emitDocComment(buf, a.documentationComment, indent: '  ');
    buf.writeln(
      '  set ${a.name}(${_typeName(a.formalParameters.first.type)} value);',
    );
  }

  buf.writeln('}');
}

// ---------------------------------------------------------------------------
// Enum

void _emitEnum(StringBuffer buf, EnumElement e) {
  _emitDocComment(buf, e.firstFragment.documentationComment);
  buf.writeln('enum ${e.name} {');
  final values = e.fields.where((f) => f.isEnumConstant).toList();
  buf.writeln('  ${values.map((f) => f.name).join(', ')},');
  buf.writeln('}');
}

// ---------------------------------------------------------------------------
// Typedef

void _emitTypeAlias(StringBuffer buf, TypeAliasElement e) {
  _emitDocComment(buf, e.firstFragment.documentationComment);
  buf.writeln(
    'typedef ${e.name}${_typeParams(e.typeParameters)} = '
    '${_typeName(e.aliasedType)};',
  );
}

// ---------------------------------------------------------------------------
// Shared helpers

void _emitMethod(StringBuffer buf, MethodElement m) {
  final mods = [
    if (m.isStatic) 'static',
    if (m.isAbstract) 'abstract',
  ].join(' ');
  buf.writeln(
    '  ${mods.isEmpty ? '' : '$mods '}${_typeName(m.returnType)} '
    '${m.name}${_typeParams(m.typeParameters)}${_params(m)};',
  );
}

String _constructor(InstanceElement enclosing, ConstructorElement c) {
  final prefix = [if (c.isConst) 'const', if (c.isFactory) 'factory'].join(' ');
  final rawName = c.name ?? '';
  final ctorName =
      (rawName == 'new' || rawName.isEmpty)
          ? enclosing.name!
          : '${enclosing.name}.$rawName';
  return '${prefix.isEmpty ? '' : '$prefix '}$ctorName${_params(c)}';
}

void _emitDocComment(StringBuffer buf, String? comment, {String indent = ''}) {
  if (comment == null || comment.isEmpty) return;
  for (final line in comment.split('\n')) {
    buf.writeln('$indent$line');
  }
}

String _typeParams(List<TypeParameterElement> params) {
  if (params.isEmpty) return '';
  final parts = params.map((p) {
    final bound = p.bound;
    return bound != null ? '${p.name} extends ${_typeName(bound)}' : p.name!;
  });
  return '<${parts.join(', ')}>';
}

/// Formats a `(params)` list for a function/method/constructor.
String _params(FunctionTypedElement e) {
  final params = e.formalParameters;
  if (params.isEmpty) return '()';

  final required = <String>[];
  final optional = <String>[];
  final named = <String>[];

  for (final p in params) {
    if (p.isRequiredPositional) {
      required.add(_param(p));
    } else if (p.isOptionalPositional) {
      optional.add(_param(p));
    } else {
      named.add(_namedParam(p));
    }
  }

  final parts = <String>[...required];
  if (optional.isNotEmpty) parts.add('[${optional.join(', ')}]');
  if (named.isNotEmpty) parts.add('{${named.join(', ')}}');
  return '(${parts.join(', ')})';
}

String _param(FormalParameterElement p) =>
    '${_typeName(p.type)} ${p.name ?? '_'}';

String _namedParam(FormalParameterElement p) {
  final req = p.isRequiredNamed ? 'required ' : '';
  return '$req${_typeName(p.type)} ${p.name ?? '_'}';
}

String _typeName(DartType type) => type.getDisplayString();
