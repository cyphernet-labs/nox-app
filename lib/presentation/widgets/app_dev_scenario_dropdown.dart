import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';

/// Debug-only dropdown that drives the gallery/demo state controls (send/sign-in
/// outcomes, list/thread/card scenarios). Wraps a `DropdownButton<T>` with the
/// shared null-guarded [onChanged] and [items] → `DropdownMenuItem` mapping (the map
/// insertion order is the menu order). With a [label] it renders a centred
/// `"<label>" + dropdown` row (the outcome selectors); without one it is the bare
/// dropdown (the scenario selectors, which the caller wraps). Presentational — the
/// caller owns any surrounding padding / `Expanded`.
class AppDevScenarioDropdown<T extends Enum> extends StatelessWidget {
  const AppDevScenarioDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.isExpanded = false,
  });

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final String? label;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final dropdown = DropdownButton<T>(
      value: value,
      isExpanded: isExpanded,
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
      items: [for (final entry in items.entries) DropdownMenuItem<T>(value: entry.key, child: Text(entry.value))],
    );
    if (label == null) return dropdown;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label!),
        SizedBox(width: AppSpacingTokens.s8),
        dropdown,
      ],
    );
  }
}
