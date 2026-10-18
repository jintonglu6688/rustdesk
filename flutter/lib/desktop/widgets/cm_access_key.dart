import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _keys = <String, LogicalKeyboardKey>{
  'Accept': LogicalKeyboardKey.keyA,
  'Cancel': LogicalKeyboardKey.keyC,
  'Disconnect': LogicalKeyboardKey.keyD,
  'Close': LogicalKeyboardKey.keyC,
  'Accept and Elevate': LogicalKeyboardKey.keyE,
  'Elevate': LogicalKeyboardKey.keyE,
  'Switch Sides': LogicalKeyboardKey.keyW,
  'Dismiss': LogicalKeyboardKey.keyC,
  'Stop voice call': LogicalKeyboardKey.keyT,
  'Audio input': LogicalKeyboardKey.keyI,
  'Chat': LogicalKeyboardKey.keyM,
  'Transfer file': LogicalKeyboardKey.keyM,
  'Enable keyboard/mouse': LogicalKeyboardKey.keyK,
  'Enable clipboard': LogicalKeyboardKey.keyB,
  'Enable audio': LogicalKeyboardKey.keyS,
  'Enable file copy and paste': LogicalKeyboardKey.keyF,
  'Enable remote restart': LogicalKeyboardKey.keyR,
  'Enable recording session': LogicalKeyboardKey.keyO,
  'Enable blocking user input': LogicalKeyboardKey.keyU,
  'Enable privacy mode': LogicalKeyboardKey.keyP,
  'OK': LogicalKeyboardKey.keyO,
  'Clear': LogicalKeyboardKey.keyL,
  'Retry': LogicalKeyboardKey.keyR,
  'Connect via relay': LogicalKeyboardKey.keyY,
  'Connect': LogicalKeyboardKey.keyN,
  'Continue': LogicalKeyboardKey.keyN,
  'Wait': LogicalKeyboardKey.keyW,
  'Request Elevation': LogicalKeyboardKey.keyE,
  'Enter Remote ID': LogicalKeyboardKey.keyI,
  'Settings': LogicalKeyboardKey.keyS,
  'General': LogicalKeyboardKey.keyG,
  'Security': LogicalKeyboardKey.keyS,
  'Network': LogicalKeyboardKey.keyN,
  'Display': LogicalKeyboardKey.keyD,
  'Account': LogicalKeyboardKey.keyA,
  'Printer': LogicalKeyboardKey.keyT,
  'About': LogicalKeyboardKey.keyB,
  'Unlock Security Settings': LogicalKeyboardKey.keyU,
  'Unlock Network Settings': LogicalKeyboardKey.keyU,
  'ID/Relay Server': LogicalKeyboardKey.keyI,
  'Socks5/Http(s) Proxy': LogicalKeyboardKey.keyP,
  'Change ID': LogicalKeyboardKey.keyI,
  'Set permanent password': LogicalKeyboardKey.keyP,
  'Login': LogicalKeyboardKey.keyL,
  'ID Server': LogicalKeyboardKey.keyI,
  'Relay Server': LogicalKeyboardKey.keyR,
  'API Server': LogicalKeyboardKey.keyA,
  'Key': LogicalKeyboardKey.keyK,
  'Password': LogicalKeyboardKey.keyP,
  'OS Password': LogicalKeyboardKey.keyW,
  'Username': LogicalKeyboardKey.keyU,
  'Remember password': LogicalKeyboardKey.keyR,
  'Close dialog': LogicalKeyboardKey.keyX,
};

String? cmAccessKey(String action) =>
    defaultTargetPlatform == TargetPlatform.windows
        ? _keys[action]?.keyLabel
        : null;

// The paired Windows engine exports this exact hint as UIA/MSAA access-key data.
String? cmAccessKeyHint(String action) =>
    cmAccessKey(action) == null ? null : 'Alt+${cmAccessKey(action)}';

TextSpan cmAccessKeyLabel(String label, String action) {
  final key = cmAccessKey(action);
  return TextSpan(
      text: label,
      children: key == null
          ? null
          : [
              const TextSpan(text: ' ('),
              TextSpan(
                  text: key,
                  style: const TextStyle(decoration: TextDecoration.underline)),
              const TextSpan(text: ')'),
            ]);
}

Widget cmAccessKeyButton(String action, String label,
    {required VoidCallback? onPressed,
    bool isOutline = false,
    Widget? icon,
    TextStyle? textStyle,
    ButtonStyle? style}) {
  return CmAccessKey(
    action: action,
    builder: (node) {
      final text = Text.rich(cmAccessKeyLabel(label, action), style: textStyle);
      final Widget button;
      if (isOutline) {
        button = icon == null
            ? OutlinedButton(
                focusNode: node,
                onPressed: onPressed,
                style: style,
                child: text)
            : OutlinedButton.icon(
                focusNode: node,
                onPressed: onPressed,
                style: style,
                icon: icon,
                label: text);
      } else {
        button = icon == null
            ? ElevatedButton(
                focusNode: node,
                onPressed: onPressed,
                style: style,
                child: text)
            : ElevatedButton.icon(
                focusNode: node,
                onPressed: onPressed,
                style: style,
                icon: icon,
                label: text);
      }
      return MergeSemantics(child: Semantics(
          button: true, hint: cmAccessKeyHint(action), child: button));
    },
  );
}

/// Access keys stay within the active focus scope and use the click callback.
class CmAccessKey extends StatefulWidget {
  final String action;
  final FocusNode? focusNode;
  final ValueChanged<FocusNode>? onInvoke;
  final Widget Function(FocusNode?) builder;

  const CmAccessKey(
      {super.key,
      required this.action,
      this.focusNode,
      this.onInvoke,
      required this.builder});

  @override
  State<CmAccessKey> createState() => _CmAccessKeyState();
}

class _CmAccessKeyState extends State<CmAccessKey> {
  final _ownedFocusNode = FocusNode();
  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _ownedFocusNode.dispose();
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    final key = _keys[widget.action];
    final primary = FocusManager.instance.primaryFocus;
    if (cmAccessKey(widget.action) == null ||
        key == null ||
        _focusNode.context == null ||
        !_focusNode.canRequestFocus ||
        (primary != _focusNode.nearestScope &&
            primary?.nearestScope != _focusNode.nearestScope) ||
        ModalRoute.of(context)?.isCurrent == false ||
        !SingleActivator(key, alt: true, includeRepeats: false)
            .accepts(event, HardwareKeyboard.instance)) {
      return false;
    }
    const intent = ActivateIntent();
    final target = _focusNode.context!;
    final action = Actions.maybeFind<ActivateIntent>(target);
    if (widget.onInvoke == null &&
        (action == null || !action.isEnabled(intent))) {
      return false;
    }
    _focusNode.requestFocus();
    if (widget.onInvoke != null) {
      widget.onInvoke!(_focusNode);
    } else {
      Actions.invoke(target, intent);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final key = cmAccessKey(widget.action);
    if (key == null) return widget.builder(widget.focusNode);
    return widget.builder(_focusNode);
  }
}
