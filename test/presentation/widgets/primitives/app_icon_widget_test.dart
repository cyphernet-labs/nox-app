import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppIconWidget', () {
    testWidgets('renders the SVG glyph it is given', (tester) async {
      await pumpApp(tester, AppIconWidget(NoxIcons.search));

      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('applies the requested size', (tester) async {
      await pumpApp(tester, AppIconWidget(NoxIcons.search, size: 48));

      final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(picture.width, 48);
      expect(picture.height, 48);
    });
  });
}
