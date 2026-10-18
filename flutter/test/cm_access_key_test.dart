import 'dart:ui' show SemanticsFlag;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/focus_aware_offstage.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/accessible_tab_navigation.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart';
import 'package:flutter_hbb/desktop/widgets/cm_access_key.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> altKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.pump();
}

void main() {
  testWidgets(
      'field access keys focus without submitting and preserve semantics',
      (tester) async {
    final passwordNode = FocusNode();
    final password = TextEditingController(text: 'unchanged');
    final server = TextEditingController(text: 'example.test');
    var submitted = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      DialogTextField(
          title: 'Password',
          accessKeyAction: 'Password',
          hintText: 'Enter your password',
          obscureText: true,
          focusNode: passwordNode,
          controller: password),
      serverSettingsTextFormField(
          label: 'ID Server',
          controller: server,
          errorMsg: '',
          showLabelText: false),
      cmAccessKeyButton('OK', 'OK', onPressed: () => submitted++),
    ]))));
    await tester.pump();
    await altKey(tester, LogicalKeyboardKey.keyI);
    final serverData =
        tester.getSemantics(find.byType(TextFormField)).getSemanticsData();
    expect(serverData.hasFlag(SemanticsFlag.isTextField), isTrue);
    expect(serverData.hasFlag(SemanticsFlag.isFocused), isTrue);
    expect(serverData.hint, 'Alt+I');
    await altKey(tester, LogicalKeyboardKey.keyP);
    expect(passwordNode.hasPrimaryFocus, isTrue);
    final passwordData = tester
        .getSemantics(find.descendant(
            of: find.byType(DialogTextField), matching: find.byType(TextField)))
        .getSemanticsData();
    expect(passwordData.hasFlag(SemanticsFlag.isObscured), isTrue);
    expect(passwordData.hint, 'Alt+P');
    expect(password.text, 'unchanged');
    expect(server.text, 'example.test');
    expect(submitted, 0);
    final okData = tester.getSemantics(find.byWidgetPredicate(
        (widget) => widget is CmAccessKey && widget.action == 'OK')).getSemanticsData();
    expect(okData.label, 'OK (O)');
    expect(okData.hint, 'Alt+O');
    expect(okData.hasFlag(SemanticsFlag.isButton), isTrue);
    await altKey(tester, LogicalKeyboardKey.keyO);
    expect(submitted, 1);
    await tester.pumpWidget(const SizedBox());
    // The binding must not dispose a focus node owned by its caller.
    passwordNode.addListener(() {});
    passwordNode.dispose();
    password.dispose();
    server.dispose();
  },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      semanticsEnabled: true);

  testWidgets(
      'category access keys keep arrow navigation and obey overlay scope',
      (tester) async {
    var selected = 0;
    var serverCalls = 0;
    var cancelCalls = 0;
    List<FocusNode> nodes = [];
    final labels = ['General', 'Network'];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
      builder: (context, setState) => Column(children: [
        AccessibleTabNavigation(
            itemCount: labels.length,
            selectedIndex: selected,
            direction: Axis.vertical,
            onSelected: (index) => setState(() => selected = index),
            builder: (values) {
              nodes = values;
              return Column(
                  children: List.generate(
                      labels.length,
                      (index) => CmAccessKey(
                          action: labels[index],
                          focusNode: nodes[index],
                          builder: (node) => Semantics(
                              tab: true,
                              selected: selected == index,
                              hint: cmAccessKeyHint(labels[index]),
                              child: InkWell(
                                  focusNode: node,
                                  onTap: () => setState(() => selected = index),
                                  child: Text(labels[index]))))));
            }),
        ExcludeFocus(
            excluding: selected != 1,
            child: cmAccessKeyButton('ID/Relay Server', 'Server',
                onPressed: () => serverCalls++)),
      ]),
    ))));
    nodes.first.requestFocus();
    await tester.pump();
    await altKey(tester, LogicalKeyboardKey.keyI);
    expect(serverCalls, 0);
    await altKey(tester, LogicalKeyboardKey.keyN);
    expect(selected, 1);
    expect(nodes[1].hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(selected, 0);
    await altKey(tester, LogicalKeyboardKey.keyN);
    await altKey(tester, LogicalKeyboardKey.keyI);
    expect(serverCalls, 1);
    final overlayScope = FocusScopeNode();
    final overlay = OverlayEntry(
        builder: (_) => Material(
            child: FocusScope(
                node: overlayScope,
                child: cmAccessKeyButton('Cancel', 'Cancel',
                    onPressed: () => cancelCalls++))));
    Overlay.of(tester.element(find.text('Server (I)'))).insert(overlay);
    await tester.pumpAndSettle();
    overlayScope.requestFocus();
    await tester.pump();
    await altKey(tester, LogicalKeyboardKey.keyG);
    await altKey(tester, LogicalKeyboardKey.keyI);
    expect(selected, 1);
    expect(serverCalls, 1);
    await altKey(tester, LogicalKeyboardKey.keyC);
    expect(cancelCalls, 1);
    overlay.remove();
    overlay.dispose();
    await tester.pumpWidget(const SizedBox());
    overlayScope.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('access key toggles and focuses the visible permission once',
      (tester) async {
    final before = FocusNode();
    var checked = false;
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
      builder: (context, setState) => Column(children: [
        TextButton(
            focusNode: before, onPressed: () {}, child: const Text('Before')),
        CmAccessKey(
            action: 'Enable keyboard/mouse',
            builder: (node) => Semantics(
                  label: 'Keyboard',
                  checked: checked,
                  hint: cmAccessKeyHint('Enable keyboard/mouse'),
                  child: InkWell(
                    key: const ValueKey('permission'),
                    focusNode: node,
                    onTap: () {
                      calls++;
                      setState(() => checked = !checked);
                    },
                    child: const Icon(Icons.keyboard),
                  ),
                )),
      ]),
    ))));
    before.requestFocus();
    await tester.pump();
    if (defaultTargetPlatform != TargetPlatform.windows) {
      await altKey(tester, LogicalKeyboardKey.keyK);
      expect(calls, 0);
      expect(cmAccessKey('Enable keyboard/mouse'), isNull);
      await tester.pumpWidget(const SizedBox());
      before.dispose();
      return;
    }
    expect(
        tester.getSemantics(find.byType(CmAccessKey)).getSemanticsData().hint,
        'Alt+K');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(checked, isTrue);
    expect(calls, 1);
    final semantics =
        tester.getSemantics(find.byType(CmAccessKey)).getSemanticsData();
    expect(semantics.hasFlag(SemanticsFlag.hasCheckedState), isTrue);
    expect(semantics.hasFlag(SemanticsFlag.isChecked), isTrue);
    expect(semantics.hint, 'Alt+K');
    expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('permission')))
            .focusNode!
            .hasFocus,
        isTrue);
    await altKey(tester, LogicalKeyboardKey.keyK);
    expect(checked, isFalse);
    await tester.pumpWidget(const SizedBox());
    before.dispose();
  },
      variant:
          TargetPlatformVariant({TargetPlatform.windows, TargetPlatform.linux}),
      semanticsEnabled: true);

  testWidgets('hidden, inactive and disabled actions cannot use access keys',
      (tester) async {
    final before = FocusNode();
    final calls = <String>[];
    Widget action(String name, {bool enabled = true}) => CmAccessKey(
          action: 'Accept',
          builder: (node) => TextButton(
              focusNode: node,
              onPressed: enabled ? () => calls.add(name) : null,
              child: Text(name)),
        );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      TextButton(
          focusNode: before, onPressed: () {}, child: const Text('Before')),
      FocusAwareOffstage(offstage: true, child: action('hidden')),
      ExcludeFocus(child: action('inactive')),
      action('disabled', enabled: false),
      action('visible'),
    ]))));
    FocusScope.of(tester.element(find.text('Before'))).requestFocus();
    await tester.pump();
    await altKey(tester, LogicalKeyboardKey.keyA);
    expect(calls, ['visible']);
    final context = tester.element(find.text('Before'));
    showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(
              content: TextField(autofocus: true),
            ));
    await tester.pumpAndSettle();
    await altKey(tester, LogicalKeyboardKey.keyA);
    expect(calls, ['visible']);
    await tester.pumpWidget(const SizedBox());
    before.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
