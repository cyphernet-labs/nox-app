@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

import '../../utils/golden.dart';

/// One consolidated golden proving stock M3 widgets pick up the NOX theme
/// (nox_component_themes.dart) with no custom classes — SC-006 / FR-009.
Widget _showcase() {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton(onPressed: () {}, child: const Text('Filled')),
          const SizedBox(height: 12),
          TextButton(onPressed: () {}, child: const Text('Text button')),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(onPressed: () {}, icon: AppIconWidget(NoxIcons.search)),
              IconButton(onPressed: () {}, icon: AppIconWidget(NoxIcons.close)),
            ],
          ),
          const SizedBox(height: 12),
          const TextField(
            decoration: InputDecoration(labelText: 'Label', helperText: 'Helper'),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('One')),
              ButtonSegment(value: 1, label: Text('Two')),
            ],
            selected: const {0},
            onSelectionChanged: (_) {},
          ),
          SwitchListTile(value: true, onChanged: (_) {}, title: const Text('Switch')),
          RadioGroup<int>(
            groupValue: 1,
            onChanged: (_) {},
            child: const RadioListTile<int>(value: 1, title: Text('Radio')),
          ),
          const SizedBox(height: 12),
          const LinearProgressIndicator(value: 0.4),
          const SizedBox(height: 12),
          const Card(
            child: Padding(padding: EdgeInsets.all(16), child: Text('Card')),
          ),
          const SizedBox(height: 12),
          const AlertDialog(title: Text('Log out?'), content: Text('This wipes your identity and local data.')),
        ],
      ),
    ),
  );
}

void main() {
  goldenTest('theme_showcase', _showcase);
}
