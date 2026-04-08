import 'package:flutter_toolkit/src/inspector/semantic_node.dart';
import 'package:flutter_toolkit/src/inspector/semantics_formatter.dart';
import 'package:test/test.dart';

// Tuple layout:
// [id, role, label, value, hint, checked, toggled, selected, enabled,
//  focused, actions, left, top, right, bottom]

void main() {
  group('parseSemanticsTree', () {
    test('parses all fields correctly', () {
      const input = '''[
        [42, "button", "Sign in", "", "Tap to log in",
         null, null, null, null, false, 1, 10.0, 20.0, 200.0, 68.0]
      ]''';

      final nodes = parseSemanticsTree(input);
      expect(nodes, hasLength(1));

      final n = nodes.first;
      expect(n.id, 42);
      expect(n.role, 'button');
      expect(n.label, 'Sign in');
      expect(n.value, '');
      expect(n.hint, 'Tap to log in');
      expect(n.checked, isNull);
      expect(n.toggled, isNull);
      expect(n.selected, isNull);
      expect(n.enabled, isNull);
      expect(n.focused, isFalse);
      expect(n.actions, 1);
      expect(n.left, 10.0);
      expect(n.top, 20.0);
      expect(n.right, 200.0);
      expect(n.bottom, 68.0);
    });

    test('supportsTap is true when actions bitmask has bit 1 set', () {
      final tappable =
          parseSemanticsTree(
            '[[1,"button","OK","","",null,null,null,null,false,1,0,0,100,48]]',
          ).first;
      final notTappable =
          parseSemanticsTree(
            '[[2,"","Info","","",null,null,null,null,false,0,0,0,100,48]]',
          ).first;

      expect(tappable.supportsTap, isTrue);
      expect(notTappable.supportsTap, isFalse);
    });

    test('describeActions decodes bitmask correctly', () {
      // tap=1, longPress=2, scrollUp=16, increase=64, decrease=128
      final node =
          parseSemanticsTree(
            '[[1,"slider","Volume","","",null,null,null,null,false,${1 + 64 + 128},0,0,300,48]]',
          ).first;
      expect(
        node.describeActions,
        containsAll(['tap', 'increase', 'decrease']),
      );
      expect(node.describeActions, isNot(contains('scrollUp')));
    });

    test('parses boolean state fields', () {
      const input = '''[
        [1,"checkbox","Remember me","","",false,null,null,null,false,0,0,0,200,48],
        [2,"checkbox","Stay signed in","","",true,null,null,null,false,0,0,52,200,100],
        [3,"toggle","Dark mode","","",null,false,null,null,false,0,0,104,200,152],
        [4,"toggle","Notifications","","",null,true,null,null,false,0,0,156,200,204]
      ]''';

      final nodes = parseSemanticsTree(input);
      expect(nodes[0].checked, isFalse);
      expect(nodes[1].checked, isTrue);
      expect(nodes[2].toggled, isFalse);
      expect(nodes[3].toggled, isTrue);
    });

    test('parses integer coordinates as doubles', () {
      final node =
          parseSemanticsTree(
            '[[0,"","Root","","",null,null,null,null,false,0,0,0,390,844]]',
          ).first;

      expect(node.left, isA<double>());
      expect(node.right, 390.0);
      expect(node.bottom, 844.0);
    });

    test('returns empty list for empty array', () {
      expect(parseSemanticsTree('[]'), isEmpty);
    });

    test('throws FormatException on malformed JSON', () {
      expect(
        () => parseSemanticsTree('[not json'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------

  group('formatSemanticsTree', () {
    SemanticNode node({
      int id = 1,
      String role = '',
      String label = '',
      String value = '',
      String hint = '',
      bool? checked,
      bool? toggled,
      bool? selected,
      bool? enabled,
      bool focused = false,
      int actions = 0,
      double width = 200,
      double height = 48,
    }) => SemanticNode(
      id: id,
      role: role,
      label: label,
      value: value,
      hint: hint,
      checked: checked,
      toggled: toggled,
      selected: selected,
      enabled: enabled,
      focused: focused,
      actions: actions,
      left: 0,
      top: 0,
      right: width,
      bottom: height,
    );

    test('formats role, id, and size', () {
      final nodes = [
        node(
          id: 2,
          role: 'button',
          label: 'Sign in',
          actions: 1,
          width: 190,
          height: 48,
        ),
      ];
      final output = formatSemanticsTree(nodes);
      expect(output, contains('[button id=2 action:tap]'));
      expect(output, contains('label: "Sign in"'));
      expect(output, contains('size: 190x48'));
    });

    test('formats plain text node (empty role)', () {
      final output = formatSemanticsTree([node(id: 5, label: 'Hello')]);
      expect(output, contains('[text id=5]'));
      expect(output, contains('label: "Hello"'));
    });

    test('includes hint and value as separate lines', () {
      final output = formatSemanticsTree([
        node(
          role: 'textfield',
          label: 'Search',
          hint: 'Enter a query',
          value: 'flutter',
        ),
      ]);
      expect(output, contains('label: "Search"'));
      expect(output, contains('hint: Enter a query'));
      expect(output, contains('value: flutter'));
    });

    test('formats checkbox states on header line', () {
      final output = formatSemanticsTree([
        node(id: 1, role: 'checkbox', label: 'Remember me', checked: false),
        node(id: 2, role: 'checkbox', label: 'Stay signed in', checked: true),
      ]);
      expect(output, contains('[checkbox id=1 unchecked]'));
      expect(output, contains('[checkbox id=2 checked]'));
    });

    test('formats toggle states on header line', () {
      final output = formatSemanticsTree([
        node(id: 1, role: 'toggle', label: 'Dark mode', toggled: false),
        node(id: 2, role: 'toggle', label: 'Notifications', toggled: true),
      ]);
      expect(output, contains('[toggle id=1 off]'));
      expect(output, contains('[toggle id=2 on]'));
    });

    test('formats selected and disabled states', () {
      final output = formatSemanticsTree([
        node(
          id: 3,
          role: 'button',
          label: 'Playlist',
          selected: true,
          actions: 1,
        ),
        node(
          id: 4,
          role: 'button',
          label: 'Submit',
          enabled: false,
          actions: 1,
        ),
      ]);
      expect(output, contains('[button id=3 selected action:tap]'));
      expect(output, contains('[button id=4 disabled action:tap]'));
    });

    test('formats focused state', () {
      final output = formatSemanticsTree([
        node(role: 'textfield', label: 'Search', focused: true),
      ]);
      expect(output, contains('focused'));
    });

    test('formats multiple actions', () {
      // scrollUp=16, scrollDown=32
      final output = formatSemanticsTree([
        node(id: 7, role: 'slider', label: 'Volume', actions: 16 + 32),
      ]);
      expect(output, contains('action:scrollUp'));
      expect(output, contains('action:scrollDown'));
    });

    test('truncates labels longer than 100 characters', () {
      final longLabel = 'A' * 105;
      final output = formatSemanticsTree([node(label: longLabel)]);
      // Should be truncated to 99 chars + ellipsis = 100 display chars.
      expect(output, contains('…'));
      expect(output, isNot(contains('A' * 105)));
    });

    test('keeps nodes with role but no label', () {
      // Buttons without labels (e.g. icon-only skip buttons) should appear.
      final output = formatSemanticsTree([
        node(id: 12, role: 'button', actions: 1),
      ]);
      expect(output, contains('[button id=12 action:tap]'));
      expect(output, isNot(contains('label:')));
    });

    test('skips nodes with no role, label, value, or hint', () {
      final output = formatSemanticsTree([
        node(id: 1), // empty everything
        node(id: 2, role: 'button', label: 'OK', actions: 1),
      ]);
      expect(output, isNot(contains('id=1')));
      expect(output, contains('id=2'));
    });

    test('returns no-content message for empty list', () {
      expect(
        formatSemanticsTree([]),
        equals('No visible text or interactive elements found.'),
      );
    });

    test('no blank lines between nodes', () {
      final output = formatSemanticsTree([
        node(id: 1, role: 'button', label: 'First', actions: 1),
        node(id: 2, role: 'button', label: 'Second', actions: 1),
      ]);
      expect(output, isNot(contains('\n\n')));
    });

    test('formats decimal sizes without trailing zeros', () {
      final output = formatSemanticsTree([
        node(id: 1, role: 'button', label: 'Tab', width: 97.5, height: 80),
      ]);
      expect(output, contains('size: 97.5x80'));
    });
  });
}
