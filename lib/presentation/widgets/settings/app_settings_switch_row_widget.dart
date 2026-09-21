import 'package:flutter/material.dart';

/// A settings on/off row: an M3 `SwitchListTile` with a title and optional
/// supporting text. `onChanged: null` renders the row disabled. Presentational.
///
/// No leading glyph. It carried one - a 40dp `secondaryContainer` circle around a
/// bell - and it was the ONLY icon on any settings row in the app: the nav rows
/// are icon-less by an owner decision the visual audit recorded and left standing,
/// and the 7.2 spec asks for a plain `SwitchListTile`. It also took enough of a
/// phone's width to wrap the supporting text under itself.
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
