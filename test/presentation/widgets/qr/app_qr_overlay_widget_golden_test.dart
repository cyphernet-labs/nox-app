@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/qr/app_qr_overlay_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest('app_qr_overlay_widget', () => const AppQrOverlayWidget());
}
