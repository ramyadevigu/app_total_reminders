import 'package:flutter/widgets.dart';

import '../theme/app_design_tokens.dart';

/// Like [IndexedStack], but cross-fades between children.
///
/// Every child stays mounted so its state survives tab switches. Inactive
/// children are fully transparent, which skips painting them, and are removed
/// from hit testing and semantics.
class FadeIndexedStack extends StatelessWidget {
  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.resolve(context, AppMotion.component);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          _FadeChild(
            active: i == index,
            duration: duration,
            child: children[i],
          ),
      ],
    );
  }
}

class _FadeChild extends StatelessWidget {
  const _FadeChild({
    required this.active,
    required this.duration,
    required this.child,
  });

  final bool active;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      excluding: !active,
      child: IgnorePointer(
        ignoring: !active,
        child: AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: duration,
          curve: AppMotion.enter,
          child: child,
        ),
      ),
    );
  }
}
