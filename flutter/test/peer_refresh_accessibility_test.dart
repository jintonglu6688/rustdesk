import 'dart:ui' show SemanticsAction, SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/peer_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('window actions expose their button role', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: MyTheme.lightTheme,
      home: Material(child: Tooltip(
        message: 'Settings',
        child: ActionIcon(icon: Icons.settings, onTap: () {}),
      )),
    ));
    final data = tester.getSemantics(find.byType(ActionIcon)).getSemanticsData();
    expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(data.tooltip, 'Settings');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
  }, semanticsEnabled: true);

  testWidgets('peer refresh exposes a named button', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Material(
          child: Tooltip(
        message: 'Refresh',
        child:
            RefreshWidget(onPressed: () {}, child: const Icon(Icons.refresh)),
      )),
    ));
    final data =
        tester.getSemantics(find.byType(RefreshWidget)).getSemanticsData();
    expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(data.hasFlag(SemanticsFlag.hasSelectedState), isFalse);
    expect(data.tooltip, 'Refresh');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
  }, semanticsEnabled: true);

  testWidgets('only declared selection exposes a selected state',
      (tester) async {
    for (final selected in <bool?>[null, false, true]) {
      await tester.pumpWidget(Semantics(
        label: 'control',
        textDirection: TextDirection.ltr,
        button: true,
        selected: selected,
        child: const SizedBox(width: 30, height: 30),
      ));
      final data =
          tester.getSemantics(find.byType(Semantics).first).getSemanticsData();
      expect(data.hasFlag(SemanticsFlag.hasSelectedState), selected != null);
      expect(data.hasFlag(SemanticsFlag.isSelected), selected == true);
    }
  }, semanticsEnabled: true);
}
