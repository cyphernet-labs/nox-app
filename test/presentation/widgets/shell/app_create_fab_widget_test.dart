import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_create_fab_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('AppCreateFabWidget shows an add glyph and fires onPressed', (tester) async {
    var taps = 0;
    await pumpApp(tester, AppCreateFabWidget(onPressed: () => taps++));

    expect(find.byType(AppIconWidget), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    expect(taps, 1);
  });
}
