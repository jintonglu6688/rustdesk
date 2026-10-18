import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/desktop/widgets/cm_keyboard_scope.dart';
import 'package:flutter_hbb/common/widgets/focus_aware_offstage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('local Tab reaches connection actions without activating them',
      (tester) async {
    final before = FocusNode();
    final accept = FocusNode();
    final disconnect = FocusNode();
    addTearDown(before.dispose);
    addTearDown(accept.dispose);
    addTearDown(disconnect.dispose);
    var accepted = 0;
    var disconnected = 0;
    await tester.pumpWidget(MaterialApp(
      home: Material(
          child: Column(children: [
        TextButton(
            focusNode: before, onPressed: () {}, child: const Text('Before')),
        CmKeyboardScope(
            child: Column(children: [
          InkWell(
              focusNode: accept,
              onTap: () => accepted++,
              child: const Text('Accept')),
          FocusAwareOffstage(
            offstage: true,
            child: InkWell(
                onTap: () => fail('hidden action was activated'),
                child: const Text('Hidden elevation')),
          ),
          InkWell(
              focusNode: disconnect,
              onTap: () => disconnected++,
              child: const Text('Disconnect')),
        ])),
      ])),
    ));
    before.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (defaultTargetPlatform != TargetPlatform.windows) {
      expect(before.hasPrimaryFocus, isTrue);
      expect(accept.canRequestFocus, isFalse);
      await tester.pumpWidget(const SizedBox());
      return;
    }
    expect(accept.hasPrimaryFocus, isTrue);
    expect(accepted, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(accepted, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(disconnect.hasPrimaryFocus, isTrue);
    expect(disconnected, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(disconnected, 1);
    await tester.pumpWidget(const SizedBox());
  },
      variant: TargetPlatformVariant(
          {TargetPlatform.windows, TargetPlatform.linux}));
}
