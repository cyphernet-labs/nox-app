import 'package:flutter/material.dart';

/// A settings on/off row: an M3 `SwitchListTile` with a title and optional
/// supporting text. `onChanged: null` renders the row disabled. Presentational.
class AppSettingsSwitchRowWidget extends StatelessWidget {
  const AppSettingsSwitchRowWidget({super.key, required this.title, required this.value, required this.onChanged, this.supportingText});

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? supportingText;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title),
      subtitle: supportingText == null ? null : Text(supportingText!),
    );
  }
}
