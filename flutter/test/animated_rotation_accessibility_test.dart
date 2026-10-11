import 'dart:ui' show SemanticsAction, SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('password refresh is a named button activated explicitly',
      (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnimatedRotationWidget(
          onPressed: () => refreshes++,
          child: const Tooltip(
            message: 'Refresh Password',
            excludeFromSemantics: true,
            child: Icon(Icons.refresh, semanticLabel: 'Refresh Password'),
          ),
        ),
      ),
    ));

    final node = tester
        .getSemantics(find.bySemanticsLabel('Refresh Password'))
        .getSemanticsData();
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.hasFlag(SemanticsFlag.hasSelectedState), isFalse);
    expect(node.hasAction(SemanticsAction.tap), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(refreshes, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(refreshes, 2);
  }, semanticsEnabled: true);
}
