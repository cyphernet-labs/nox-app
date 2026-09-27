import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// A settings on/off row: an M3 `SwitchListTile` with a title, optional
/// supporting text and a bare leading glyph. `onChanged: null` renders the row
/// disabled. Presentational.
///
/// The glyph has been through both reversals its neighbours have: removed while
/// settings rows were icon-less, brought back when that rule was, and now without
/// the 40dp tinted circle the corpus draws around it - which the owner dropped
/// for the whole screen.
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
          : AppIconWidget(leadingIcon!, size: AppDimensionTokens.icon.base, color: colorScheme.onSurfaceVariant),
    );
  }
}
