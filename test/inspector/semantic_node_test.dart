import 'package:flutter_toolkit/src/inspector/semantic_node.dart';
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
}
