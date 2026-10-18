import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// State shared by the remote canvas and its keyboard menu on Windows.
class WindowsKeyboardControl {
  static const option = 'local-keyboard-shortcut';
  static const keys = {
    'F8': LogicalKeyboardKey.f8,
    'F9': LogicalKeyboardKey.f9,
    'F10': LogicalKeyboardKey.f10,
    'F11': LogicalKeyboardKey.f11,
  };

  final local = false.obs;
  final shortcut = 'F11'.obs;
  final menuFocus = FocusNode(debugLabel: 'Keyboard control');
  bool Function(bool local)? onSwitch;
  bool Function()? canHandleShortcut;
  Future<bool> Function()? activateSession;
  String Function()? readShortcut;
  LogicalKeyboardKey? _consumed;
  bool _resumePending = false;

  String get shortcutLabel => 'Ctrl+Shift+${shortcut.value}';

  void setShortcut(String value) {
    shortcut.value = keys.containsKey(value) ? value : 'F11';
  }

  void refreshShortcut() {
    final value = readShortcut?.call();
    if (value != null) setShortcut(value);
  }

  bool switchTo(bool value) {
    if (value == local.value) return true;
    if (onSwitch?.call(value) != true) return false;
    local.value = value;
    return true;
  }

  /// Windows has activated the saved window and released the complete chord.
  Future<void> resumeFromGlobalShortcut() async {
    cancelPendingResume();
    if (!local.value || await activateSession?.call() != true) return;
    if (canHandleShortcut?.call() == true) switchTo(false);
  }

  /// Called both before Flutter forwards input and for local toolbar focus.
  /// Latching the trigger makes these two callers and key repeat idempotent.
  bool handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && keys.containsValue(event.logicalKey)) {
      refreshShortcut();
    }
    final keyboard = HardwareKeyboard.instance;
    final consumed = event.logicalKey == _consumed;
    if (consumed && event is KeyUpEvent) _consumed = null;
    if (_resumePending &&
        _consumed == null &&
        !keyboard.isControlPressed &&
        !keyboard.isShiftPressed) {
      _resumePending = false;
      scheduleMicrotask(() {
        if (canHandleShortcut?.call() == true) switchTo(false);
      });
    }
    if (consumed) return true;
    if (canHandleShortcut?.call() != true || event.synthesized) return false;
    if (event is! KeyDownEvent ||
        event.logicalKey != keys[shortcut.value] ||
        !keyboard.isControlPressed ||
        !keyboard.isShiftPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) return false;
    _consumed = event.logicalKey;
    if (local.value) {
      // Keep every key-up of this chord local before reacquiring capture.
      _resumePending = true;
    } else {
      switchTo(true);
    }
    return true;
  }

  void cancelPendingResume() {
    _resumePending = false;
    _consumed = null;
  }

  void dispose() {
    cancelPendingResume();
    onSwitch = null;
    canHandleShortcut = null;
    activateSession = null;
    readShortcut = null;
    menuFocus.dispose();
  }
}
