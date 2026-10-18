import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/windows_keyboard_control.dart';

void main() {
  testWidgets('global resume activates the saved session before enabling input',
      (tester) async {
    final control = WindowsKeyboardControl();
    final changes = <bool>[];
    var foreground = false;
    control.local.value = true;
    control.canHandleShortcut = () => foreground;
    control.onSwitch = (local) {
      changes.add(local);
      return true;
    };
    control.activateSession = () async {
      expect(changes, isEmpty);
      foreground = true;
      return true;
    };
    addTearDown(control.dispose);
    await control.resumeFromGlobalShortcut();
    expect(changes, [false]);
    expect(control.local.value, isFalse);
  });

  testWidgets('global resume stays local when activation or page checks fail',
      (tester) async {
    final control = WindowsKeyboardControl();
    control.local.value = true;
    control.onSwitch = (_) => throw StateError('Remote input must stay disabled');
    control.canHandleShortcut = () => true;
    control.activateSession = () async => false;
    addTearDown(control.dispose);
    await control.resumeFromGlobalShortcut();
    expect(control.local.value, isTrue);
    control.activateSession = () async => true;
    control.canHandleShortcut = () => false;
    await control.resumeFromGlobalShortcut();
    expect(control.local.value, isTrue);
  });

  testWidgets('switches once per chord and resumes only after all keys are up',
      (tester) async {
    final control = WindowsKeyboardControl();
    final changes = <bool>[];
    control.canHandleShortcut = () => true;
    control.onSwitch = (local) {
      changes.add(local);
      return true;
    };
    HardwareKeyboard.instance.addHandler(control.handleKeyEvent);
    addTearDown(() {
      HardwareKeyboard.instance.removeHandler(control.handleKeyEvent);
      control.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f11);
    expect(changes, [true]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f11);
    await tester.pump();
    expect(control.local.value, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlRight);
    await tester.pump();
    expect(control.local.value, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftRight);
    await tester.pump();
    expect(changes, [true, false]);
  });

  testWidgets(
      'inactive or blocked pages cannot resume, including a pending chord',
      (tester) async {
    final control = WindowsKeyboardControl();
    var active = true;
    control.canHandleShortcut = () => active;
    control.onSwitch = (_) => active;
    control.switchTo(true);
    HardwareKeyboard.instance.addHandler(control.handleKeyEvent);
    addTearDown(() {
      HardwareKeyboard.instance.removeHandler(control.handleKeyEvent);
      control.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f11);
    active = false;
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(control.local.value, isTrue);
    expect(control.switchTo(false), isFalse);
  });

  testWidgets('configured chord is used and extra Alt does not trigger it',
      (tester) async {
    final control = WindowsKeyboardControl();
    // Another session window changed the shared preference since construction.
    control.readShortcut = () => 'F9';
    control.canHandleShortcut = () => true;
    control.onSwitch = (_) => true;
    HardwareKeyboard.instance.addHandler(control.handleKeyEvent);
    addTearDown(() {
      HardwareKeyboard.instance.removeHandler(control.handleKeyEvent);
      control.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    expect(control.local.value, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    expect(control.local.value, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    expect(control.local.value, isTrue);
    expect(control.shortcutLabel, 'Ctrl+Shift+F9');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });
}
