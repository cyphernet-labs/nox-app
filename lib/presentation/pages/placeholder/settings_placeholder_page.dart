import 'package:flutter/material.dart';
import 'package:nox_app/general/l10n_extension.dart';

/// Skeleton placeholder for the Settings tab. Profile-like items live in
/// Settings (no separate profile screen); real content is a later feature.
class SettingsPlaceholderPage extends StatelessWidget {
  const SettingsPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(context.l10n.settings));
  }
}
