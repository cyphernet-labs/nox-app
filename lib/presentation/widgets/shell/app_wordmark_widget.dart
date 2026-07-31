import 'package:flutter/material.dart';
import 'package:nox_app/general/l10n_extension.dart';

/// The "NOX" wordmark. Roboto Bold 700, letter spacing +[letterSpacingEm] over the
/// `titleLarge` role. Defaults to the chats app-bar size (`titleLarge`, ~22); a
/// [fontSize] override drives the smaller desktop-titlebar wordmark (13, +0.14em) and
/// the larger splash wordmark (28). Source: nox_scaffold.dart `NoxWordmark`.
class AppWordmarkWidget extends StatelessWidget {
  const AppWordmarkWidget({super.key, this.color, this.fontSize, this.letterSpacingEm = _defaultLetterSpacingEm});

  final Color? color;

  /// Overrides the wordmark size; null → the `titleLarge` size (~22).
  final double? fontSize;

  /// Letter spacing as a fraction of the resolved font size.
  final double letterSpacingEm;

  static const double _defaultLetterSpacingEm = 0.12;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.titleLarge;
    final size = fontSize ?? base?.fontSize ?? 22;
    return Text(
      context.l10n.appName,
      style: base?.copyWith(
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: letterSpacingEm * size,
        color: color ?? colorScheme.onSurface,
      ),
    );
  }
}
