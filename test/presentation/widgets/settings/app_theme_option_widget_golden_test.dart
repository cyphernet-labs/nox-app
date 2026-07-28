@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/settings/app_theme_option_widget.dart';

import '../../../utils/golden.dart';

/// A neutral stand-in for the appearance page's private `_ThemePreview` — a fixed-size
/// leading box (mirrors the real ~96×76 preview). The golden locks the option chrome
/// (selected border, label, caption, radio), not the preview internals.
Widget _preview(Color color) => Container(
  width: 96,
  height: 76,
  decoration: BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: Colors.grey),
  ),
);

void main() {
  // Stacked full-width like the real appearance page (the option's inner text Column is
  // mainAxisSize.max, so each option is wrapped in IntrinsicHeight to hug its content
  // height rather than stretching to fill the test surface).
  goldenTest(
    'app_theme_option_widget',
    () => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Selected — shows the selection ring/accent.
          IntrinsicHeight(
            child: AppThemeOptionWidget(
              label: 'Light',
              caption: 'Bright surfaces',
              selected: true,
              preview: _preview(Colors.white),
              onTap: () {},
            ),
          ),
          const SizedBox(height: 12),
          // Unselected — the resting chrome.
          IntrinsicHeight(
            child: AppThemeOptionWidget(
              label: 'Dark',
              caption: 'Dim surfaces',
              selected: false,
              preview: _preview(Colors.black),
              onTap: () {},
            ),
          ),
        ],
      ),
    ),
  );
}
