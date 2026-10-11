import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A single Tab stop with arrow navigation inside a desktop tab control.
class AccessibleTabNavigation extends StatefulWidget {
  final int itemCount;
  final int selectedIndex;
  final Axis direction;
  final ValueChanged<int> onSelected;
  final Widget Function(List<FocusNode>) builder;

  const AccessibleTabNavigation({
    super.key,
    required this.itemCount,
    required this.selectedIndex,
    required this.direction,
    required this.onSelected,
    required this.builder,
  });

  @override
  State<AccessibleTabNavigation> createState() =>
      _AccessibleTabNavigationState();
}

class _AccessibleTabNavigationState extends State<AccessibleTabNavigation> {
  final List<FocusNode> _nodes = [];

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final current = _nodes.indexWhere((node) => node.hasPrimaryFocus);
    if (current < 0) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final previous = widget.direction == Axis.horizontal
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowUp;
    final next = widget.direction == Axis.horizontal
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowDown;
    final int target;
    if (key == previous) {
      target = (current - 1 + _nodes.length) % _nodes.length;
    } else if (key == next) {
      target = (current + 1) % _nodes.length;
    } else if (key == LogicalKeyboardKey.home) {
      target = 0;
    } else if (key == LogicalKeyboardKey.end) {
      target = _nodes.length - 1;
    } else {
      return KeyEventResult.ignored;
    }
    widget.onSelected(target);
    _nodes[target].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    while (_nodes.length < widget.itemCount) {
      _nodes.add(FocusNode());
    }
    while (_nodes.length > widget.itemCount) {
      _nodes.removeLast().dispose();
    }
    for (var i = 0; i < _nodes.length; i++) {
      _nodes[i].skipTraversal = i != widget.selectedIndex;
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      tabBar: true,
      verticalTabBar: widget.direction == Axis.vertical,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onKeyEvent: _onKey,
        child: widget.builder(_nodes),
      ),
    );
  }
}
