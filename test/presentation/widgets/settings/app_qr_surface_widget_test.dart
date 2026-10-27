import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/presentation/widgets/settings/app_qr_surface_widget.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppQrSurfaceWidget', () {
    testWidgets('renders the brand-fixed light surface as a semantic image', (tester) async {
      await pumpApp(tester, const AppQrSurfaceWidget(data: 'NOX-abc-123'));

      expect(find.byType(AppQrSurfaceWidget), findsOneWidget);
      final semantics = tester.getSemantics(find.byType(AppQrSurfaceWidget));
      expect(semantics.label, isNotEmpty);
    });

    testWidgets('renders a real scannable QR (QrImageView), not a placeholder painter', (tester) async {
      await pumpApp(tester, const AppQrSurfaceWidget(data: 'alice'));

      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('uses the brand qr-surface color regardless of theme (not the ColorScheme)', (tester) async {
      await pumpApp(tester, const AppQrSurfaceWidget(data: 'NOX-abc-123'), themeMode: ThemeMode.dark);

      final container = tester.widget<Container>(
        find.descendant(of: find.byType(AppQrSurfaceWidget), matching: find.byType(Container)).first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, NoxBrand.qrSurface);
    });
  });
}
