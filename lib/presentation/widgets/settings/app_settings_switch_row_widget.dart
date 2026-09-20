import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// A settings on/off row: an M3 `SwitchListTile` with a title, optional
/// supporting text and the 40dp circular `secondaryContainer` chip the corpus
/// draws in front of it. `onChanged: null` renders the row disabled.
/// Presentational.
///
/// The chip was briefly removed, on the grounds that this was the only settings
/// row in the app carrying a glyph while the nav rows were icon-less. The owner
/// reversed that: every settings row leads with a chip now, so the odd one out
/// would be this row WITHOUT one.
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
                child: AppIconWidget(leadingIcon!, size: AppDimensionTokens.icon.lg, color: colorScheme.onSecondaryContainer),
              ),
            ),
    );
  }
}
