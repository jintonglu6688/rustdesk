import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Keyboard traversal for the local connection authorization panel.
class CmKeyboardScope extends StatelessWidget {
  final Widget child;

  const CmKeyboardScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return ExcludeFocus(excluding: true, child: child);
    }
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: child,
    );
  }
}
