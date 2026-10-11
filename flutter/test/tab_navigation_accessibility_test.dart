import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/accessible_tab_navigation.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pressTab(WidgetTester tester, {bool backwards = false}) async {
  if (backwards) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (backwards) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

void main() {
  for (final direction in Axis.values) {
    testWidgets('$direction tabs have one Tab stop and arrow selection',
        (tester) async {
      final before = FocusNode();
      final content = FocusNode();
      List<FocusNode> tabs = [];
      var selected = 0;
      final count = direction == Axis.horizontal ? 2 : 3;
      await tester.pumpWidget(MaterialApp(
        home: Material(child: StatefulBuilder(builder: (context, setState) {
          return FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: Column(children: [
              TextButton(
                  focusNode: before,
                  onPressed: () {},
                  child: const Text('Before')),
              AccessibleTabNavigation(
                itemCount: count,
                selectedIndex: selected,
                direction: direction,
                onSelected: (index) => setState(() => selected = index),
                builder: (nodes) {
                  tabs = nodes;
                  final items = List.generate(
                      count,
                      (index) => Semantics(
                            container: true,
                            tab: true,
                            selected: selected == index,
                            child: InkWell(
                              key: ValueKey('tab-$index'),
                              focusNode: nodes[index],
                              onTap: () => setState(() => selected = index),
                              child: Text('Category $index'),
                            ),
                          ));
                  return SizedBox(
                    height: 120,
                    width: 400,
                    child: ListView(scrollDirection: direction, children: items),
                  );
                },
              ),
              TextField(
                  focusNode: content,
                  decoration: InputDecoration(labelText: 'Content $selected')),
            ]),
          );
        })),
      ));
      before.requestFocus();
      await tester.pump();
      await pressTab(tester);
      expect(tabs[0].hasPrimaryFocus, isTrue);
      final next = direction == Axis.horizontal
          ? LogicalKeyboardKey.arrowRight
          : LogicalKeyboardKey.arrowDown;
      await tester.sendKeyEvent(next);
      await tester.pump();
      expect(selected, 1);
      expect(tabs[1].hasPrimaryFocus, isTrue);
      final group = tester
          .getSemantics(find.byType(AccessibleTabNavigation))
          .getSemanticsData();
      expect(group.hasFlag(SemanticsFlag.isTabBar), isTrue);
      expect(group.hasFlag(SemanticsFlag.isVerticalTabBar),
          direction == Axis.vertical);
      final item = tester
          .getSemantics(find.byKey(const ValueKey('tab-1')))
          .getSemanticsData();
      expect(item.hasFlag(SemanticsFlag.isTab), isTrue);
      expect(item.hasFlag(SemanticsFlag.isSelected), isTrue);
      expect(item.label, 'Category 1');
      await pressTab(tester);
      expect(content.hasPrimaryFocus, isTrue);
      expect(find.text('Content 1'), findsOneWidget);
      await tester.sendKeyEvent(next);
      await tester.pump();
      expect(selected, 1);
      await pressTab(tester, backwards: true);
      expect(tabs[1].hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(selected, count - 1);
      await tester.sendKeyEvent(next);
      await tester.pump();
      expect(selected, 0);
      expect(tabs[0].hasPrimaryFocus, isTrue);
      // Accessibility focus alone must not select another page.
      tabs[1].requestFocus();
      await tester.pump();
      expect(selected, 0);
      await tester.pumpWidget(const SizedBox());
      before.dispose();
      content.dispose();
    }, semanticsEnabled: true);
  }

  testWidgets('window controls leave Tab order but keep accessible actions',
      (tester) async {
    final before = FocusNode();
    final after = FocusNode();
    var clicks = 0;
    await tester.pumpWidget(MaterialApp(
      theme: MyTheme.lightTheme,
      home: Material(
          child: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: Row(children: [
          TextButton(
              focusNode: before, onPressed: () {}, child: const Text('Before')),
          Tooltip(
              message: 'Minimize',
              child: ActionIcon(
                skipTraversal: true,
                icon: Icons.minimize,
                onTap: () => clicks++,
              )),
          TextButton(
              focusNode: after, onPressed: () {}, child: const Text('After')),
        ]),
      )),
    ));
    before.requestFocus();
    await tester.pump();
    await pressTab(tester);
    expect(after.hasPrimaryFocus, isTrue);
    await pressTab(tester, backwards: true);
    expect(before.hasPrimaryFocus, isTrue);
    final semantics =
        tester.getSemantics(find.byType(ActionIcon)).getSemanticsData();
    expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(semantics.tooltip, 'Minimize');
    await tester.tap(find.byType(ActionIcon));
    expect(clicks, 1);
    await tester.pumpWidget(const SizedBox());
    before.dispose();
    after.dispose();
  }, semanticsEnabled: true);
}
