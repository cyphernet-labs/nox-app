import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/primitives/app_file_glyph_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/file_type.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('AppFileGlyphWidget renders the type icon', (tester) async {
    await pumpApp(tester, const AppFileGlyphWidget(type: FileType.pdf));

    expect(find.byType(AppIconWidget), findsOneWidget);
  });
}
