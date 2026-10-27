@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/settings/app_qr_surface_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // Brand-fixed light surface (#FFFFFF / #0C0C0C): the light and dark baselines
  // are intentionally identical (it sits outside the ColorScheme).
  goldenTest('app_qr_surface_widget', () => const Center(child: AppQrSurfaceWidget(data: 'NOX-7c1f9a4e-User7421')));
}
