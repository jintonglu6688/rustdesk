import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/focus_aware_offstage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Tab skips hidden controls and reaches them when shown',
      (tester) async {
    final first = FocusNode();
    final hidden = FocusNode();
    final last = FocusNode();
    addTearDown(first.dispose);
    addTearDown(hidden.dispose);
    addTearDown(last.dispose);
    var actions = 0;
    for (final offstage in [true, false]) {
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Column(children: [
            TextButton(
                focusNode: first, onPressed: () {}, child: const Text('First')),
            FocusAwareOffstage(
              offstage: offstage,
              child: TextButton(
                focusNode: hidden,
                onPressed: () => actions++,
                child: const Text('Conditional action'),
              ),
            ),
            TextButton(
                focusNode: last, onPressed: () {}, child: const Text('Last')),
          ]),
        ),
      ));
      first.requestFocus();
      await tester.pump();
      for (final expected in offstage ? [last, first] : [hidden, last, first]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, expected);
        expect(actions, 0);
      }
      for (final expected in offstage ? [last, first] : [last, hidden, first]) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, expected);
        expect(actions, 0);
      }
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(actions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
