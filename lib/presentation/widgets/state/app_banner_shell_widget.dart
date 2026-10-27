import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';

/// Thin shell for the app's FULL-BLEED notice strip — a `surfaceContainer`
/// [Material] at `NoxElevation.level3` wrapping a padded [Row]. It reads as a
/// layered band beneath the chrome and sidesteps `MaterialBanner`'s
/// non-empty-actions rule. Callers own the row content (glyph + text + action).
///
/// One caller now: [AppNoticeStripWidget], the offline strip directly under the
/// chats chrome, where edge-to-edge is right because the band belongs to the
/// chrome. `AppInfoBannerWidget` left it - on a settings screen the same slab ran
/// edge to edge over inset cards and looked like nothing else there.
class AppBannerShellWidget extends StatelessWidget {
  const AppBannerShellWidget({
    super.key,
    required this.padding,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final EdgeInsets padding;
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainer,
      elevation: NoxElevation.level3,
      child: Padding(
        padding: padding,
        child: Row(crossAxisAlignment: crossAxisAlignment, children: children),
      ),
    );
  }
}
