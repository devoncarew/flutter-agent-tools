import 'package:flutter_agent_tools/src/inspector/semantics_formatter.dart';
import 'package:test/test.dart';

// Tuple layout:
// [id, role, label, value, hint, checked, toggled, selected, enabled,
//  focused, actions, left, top, right, bottom]

void main() {
  group('formatSemanticsTree', () {
    test('formats buttons and text', () {
      const input = '''[
        [1,"","Podtastic","","",null,null,null,null,false,0,0,0,390,844],
        [2,"button","Sign in","","",null,null,null,null,false,1,100,200,290,248],
        [3,"textfield","Email address","","Enter your email",null,null,null,null,false,0,100,260,290,308]
      ]''';

      const expected = '''
[text]        Podtastic
[button]      Sign in
[textfield]   Email address (hint: Enter your email)
''';

      expect(formatSemanticsTree(input), equals(expected.trim()));
    });

    test('formats checkbox states', () {
      const input = '''[
        [1,"checkbox","Remember me","","",false,null,null,null,false,0,0,0,200,48],
        [2,"checkbox","Stay signed in","","",true,null,null,null,false,0,0,52,200,100]
      ]''';

      const expected = '''
[checkbox]    Remember me (unchecked)
[checkbox]    Stay signed in (checked)
''';

      expect(formatSemanticsTree(input), equals(expected.trim()));
    });

    test('formats toggle states', () {
      const input = '''[
        [1,"toggle","Dark mode","","",null,false,null,null,false,0,0,0,300,48],
        [2,"toggle","Notifications","","",null,true,null,null,false,0,0,52,300,100]
      ]''';

      const expected = '''
[toggle]      Dark mode (off)
[toggle]      Notifications (on)
''';

      expect(formatSemanticsTree(input), equals(expected.trim()));
    });

    test('shows value alongside label', () {
      const input = '''[
        [1,"slider","Volume","75","",null,null,null,null,false,64,0,0,300,48]
      ]''';

      const expected = '[slider]      Volume (value: 75)';

      expect(formatSemanticsTree(input), equals(expected.trim()));
    });

    test('shows focused state', () {
      const input = '''[
        [1,"textfield","Search","","",null,null,null,null,true,0,0,0,300,48]
      ]''';

      expect(formatSemanticsTree(input), contains('(focused)'));
    });

    test('uses value as display text when label is empty', () {
      const input = '''[
        [1,"","","42%","",null,null,null,null,false,0,0,0,200,48]
      ]''';

      expect(formatSemanticsTree(input), contains('42%'));
    });

    test('skips nodes with no content', () {
      const input = '''[
        [1,"","","","",null,null,null,null,false,0,0,0,390,844],
        [2,"button","Sign in","","",null,null,null,null,false,1,0,0,200,48]
      ]''';

      final output = formatSemanticsTree(input);
      expect(output.split('\n').where((l) => l.isNotEmpty), hasLength(1));
      expect(output, contains('[button]'));
    });

    test('returns error string on error prefix', () {
      const input = 'error:semantics not enabled';
      expect(formatSemanticsTree(input), equals(input));
    });

    test('returns error on malformed JSON', () {
      const input = '[not valid json';
      expect(formatSemanticsTree(input), startsWith('error:'));
    });

    test('returns no-content message for empty tree', () {
      const input = '[]';
      expect(
        formatSemanticsTree(input),
        equals('No visible text or interactive elements found.'),
      );
    });

    test('mixed roles produce correct role labels', () {
      const input = '''[
        [1,"header","Settings","","",null,null,null,null,false,0,0,0,390,48],
        [2,"image","Profile photo","","",null,null,null,null,false,0,0,52,80,132],
        [3,"link","Privacy policy","","",null,null,null,null,false,1,0,200,390,248]
      ]''';

      final output = formatSemanticsTree(input);
      expect(output, contains('[header]'));
      expect(output, contains('[image]'));
      expect(output, contains('[link]'));
    });
  });
}
