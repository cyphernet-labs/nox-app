import 'package:flutter/material.dart';
import 'package:nox_app/general/l10n_extension.dart';

/// The "NOX" wordmark for the chats app-bar title. Roboto Bold 700, letter
/// spacing +0.12em over the `titleLarge` role. Source: nox_scaffold.dart `NoxWordmark`.
class AppWordmarkWidget extends StatelessWidget {
  const AppWordmarkWidget({super.key, this.color});

  final Color? color;

  static const double _letterSpacingEm = 0.12;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.titleLarge;
    final fontSize = base?.fontSize ?? 22;
    return Text(
      context.l10n.appName,
      style: base?.copyWith(fontWeight: FontWeight.w700, letterSpacing: _letterSpacingEm * fontSize, color: color ?? colorScheme.onSurface),
    );
  }
}
