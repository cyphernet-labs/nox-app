import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/qr/app_qr_overlay_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('renders the aim instruction over a reticle', (tester) async {
    await pumpApp(tester, const AppQrOverlayWidget());

    expect(find.text(TextConstants.qrAimHint), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
