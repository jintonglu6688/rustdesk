import 'package:flutter/widgets.dart';

/// Keeps hidden controls mounted without leaving them in keyboard navigation.
class FocusAwareOffstage extends StatelessWidget {
  final bool offstage;
  final Widget? child;

  const FocusAwareOffstage({super.key, this.offstage = true, this.child});

  @override
  Widget build(BuildContext context) => ExcludeFocus(
        excluding: offstage,
        child: Offstage(offstage: offstage, child: child),
      );
}
