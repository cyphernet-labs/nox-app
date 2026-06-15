import 'package:flutter/material.dart';

/// Single-select segmented control — a thin generic over the stock M3
/// `SegmentedButton` (the theme provides the selected `secondaryContainer` fill
/// + shape). Source: `NoxSegmented`.
class AppSegmentedWidget<T> extends StatelessWidget {
  const AppSegmentedWidget({super.key, required this.options, required this.selected, required this.onChanged});

  final Map<T, String> options; // {value: label}
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<T>(
      segments: [for (final entry in options.entries) ButtonSegment<T>(value: entry.key, label: Text(entry.value))],
      selected: {selected},
      showSelectedIcon: true,
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) onChanged(selection.first);
      },
    );
  }
}
