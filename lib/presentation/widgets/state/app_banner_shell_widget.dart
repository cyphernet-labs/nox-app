import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';

/// Thin shared shell for the app's inline banners — a `surfaceContainer` [Material]
/// at `NoxElevation.level3` wrapping a padded [Row]. It reads as a layered banner
/// beneath the chrome and sidesteps `MaterialBanner`'s non-empty-actions rule.
/// Callers own the row content (glyph + text + action); this only unifies the
/// surface/elevation/padding/row scaffold shared by the notice strip and the info
/// banner. [crossAxisAlignment] defaults to `center` (single-line notice); the
/// multi-line info banner passes `start`.
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
