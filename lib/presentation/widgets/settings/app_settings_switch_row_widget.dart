import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// A settings on/off row: an M3 `SwitchListTile` with a title and optional
/// supporting text. `onChanged: null` renders the row disabled. When
/// [leadingIcon] is non-null, a 40dp circular `secondaryContainer` chip carrying
/// that glyph is rendered as the row's leading (e.g. the 7.2 Notifications bell).
/// Presentational.
class AppSettingsSwitchRowWidget extends StatelessWidget {
  const AppSettingsSwitchRowWidget({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.supportingText,
    this.leadingIcon,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? supportingText;
  final SvgGenImage? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title),
      subtitle: supportingText == null ? null : Text(supportingText!),
      secondary: leadingIcon == null
          ? null
          : Container(
              width: AppDimensionTokens.size.avatarSm,
              height: AppDimensionTokens.size.avatarSm,
              decoration: BoxDecoration(shape: BoxShape.circle, color: colorScheme.secondaryContainer),
              child: Center(
                child: AppIconWidget(leadingIcon!, size: AppDimensionTokens.icon.base, color: colorScheme.onSecondaryContainer),
              ),
            ),
    );
  }
}
