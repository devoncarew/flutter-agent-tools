import 'dart:convert';
import 'dart:io';

import 'package:flutter_agent_tools/src/inspector/error_summarizers.dart';
import 'package:flutter_agent_tools/src/inspector/app_session.dart';
import 'package:test/test.dart';

FlutterError _loadError(String name) {
  final data =
      jsonDecode(
            File('test/inspector/fixtures/errors/$name').readAsStringSync(),
          )
          as Map<String, dynamic>;
  return FlutterError.tryParse(data)!;
}

void main() {
  final overflowError = _loadError('overflow_error.json');
  final unboundedViewport = _loadError('unbounded_viewport.json');
  final failedAssertion = _loadError('failed_assertion.json');
  final nullCheck = _loadError('null_check.json');

  group('compactSummarizer', () {
    test('overflow_error', () {
      expect(
        compactSummarizer(overflowError),
        equals('''
A RenderFlex overflowed by 900 pixels on the bottom.
The relevant error-causing widget was:
  Column Column:file:///Users/.../flight_check/example/lib/main.dart:367:16
The specific RenderFlex in question is: RenderFlex#d014f relayoutBoundary=up2 OVERFLOWING
  constraints: BoxConstraints(0.0<=w<=411.0, h=300.0)
  size: Size(411.0, 300.0)
  direction: vertical
  widget ID: inspector-10'''),
      );
    });

    test('unbounded_viewport', () {
      expect(
        compactSummarizer(unboundedViewport),
        equals('Vertical viewport was given unbounded height.'),
      );
    });

    test('failed_assertion', () {
      expect(
        compactSummarizer(failedAssertion),
        equals(
          r'''
Manually triggered assertion failure from Profile page.\n'package:flight_check_example/main.dart':\nFailed assertion: line 299 pos 15: 'false'
At: #2      _ProfilePage.build.<anonymous closure> (package:flight_check_example/main.dart:299:15)''',
        ),
      );
    });

    test('null_check', () {
      expect(
        compactSummarizer(nullCheck),
        equals(
          '''
Null check operator used on a null value
At: #0      _ProfilePage.build.<anonymous closure> (package:flight_check_example/main.dart:311:28)''',
        ),
      );
    });
  });

  group('detailedSummarizer', () {
    test('overflow_error', () {
      expect(
        detailedSummarizer(overflowError),
        equals('''
Exception caught by rendering library
A RenderFlex overflowed by 900 pixels on the bottom.
The relevant error-causing widget was:
  Column Column:file:///Users/.../flight_check/example/lib/main.dart:367:16
The overflowing RenderFlex has an orientation of Axis.vertical.
The edge of the RenderFlex that is overflowing has been marked in the rendering with a yellow and black striped pattern. This is usually caused by the contents being too big for the RenderFlex.
Hint: Consider applying a flex factor (e.g. using an Expanded widget) to force the children of the RenderFlex to fit within the available space instead of being sized to their natural size.
Hint: This is considered an error condition because it indicates that there is content that cannot be seen. If the content is legitimately bigger than the available space, consider clipping it with a ClipRect widget before putting it in the flex, or using a scrollable container rather than a Flex, like a ListView.
The specific RenderFlex in question is: RenderFlex#d014f relayoutBoundary=up2 OVERFLOWING
  constraints: BoxConstraints(0.0<=w<=411.0, h=300.0)
  size: Size(411.0, 300.0)
  direction: vertical
  widget ID: inspector-10'''),
      );
    });

    test('unbounded_viewport', () {
      expect(
        detailedSummarizer(unboundedViewport),
        equals(
          '''
Exception caught by rendering library
Vertical viewport was given unbounded height.
Viewports expand in the scrolling direction to fill their container. In this case, a vertical viewport was given an unlimited amount of vertical space in which to expand. This situation typically happens when a scrollable widget is nested inside another scrollable widget.
Hint: If this widget is always nested in a scrollable widget there is no need to use a viewport because there will always be enough vertical space for the children. In this case, consider using a Column or Wrap instead. Otherwise, consider using a CustomScrollView to concatenate arbitrary slivers into a single scrollable.''',
        ),
      );
    });

    test('failed_assertion', () {
      expect(
        detailedSummarizer(failedAssertion),
        equals(r'''
Exception caught by gesture
Manually triggered assertion failure from Profile page.\n'package:flight_check_example/main.dart':\nFailed assertion: line 299 pos 15: 'false'
At: #2      _ProfilePage.build.<anonymous closure> (package:flight_check_example/main.dart:299:15)
Handler: ""onTap""
Recognizer: TapGestureRecognizer#afde5'''),
      );
    });
  });
}
