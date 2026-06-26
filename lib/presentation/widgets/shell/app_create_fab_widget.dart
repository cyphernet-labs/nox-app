import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// The docked "+" FAB (create chat) that cradles into the bottom-bar notch.
/// `primaryContainer`, elevation 3, circle; visible on both tabs (it's an
/// action, not a tab). Source: nox_scaffold.dart `NoxCreateFab`.
class AppCreateFabWidget extends StatelessWidget {
  const AppCreateFabWidget({super.key, this.onPressed});

  final VoidCallback? onPressed;

  static double get _iconSize => AppDimensionTokens.icon.fab;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FloatingActionButton(
      onPressed: onPressed,
      tooltip: TextConstants.tooltipCreateChat,
      backgroundColor: colorScheme.primaryContainer,
      foregroundColor: colorScheme.onPrimaryContainer,
      elevation: NoxElevation.level3,
      shape: const CircleBorder(),
      child: AppIconWidget(NoxIcons.add, size: _iconSize, color: colorScheme.onPrimaryContainer),
    );
  }
}
