import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/shell/app_detail_scaffold_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  testWidgets('renders title + back and fills width on a narrow window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(
      tester,
      AppDetailScaffoldWidget(
        title: 'Settings',
        body: Container(key: const Key('body')),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.byTooltip(l10nEn.tooltipBack), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('body'))).width, 420);
  });

  testWidgets('caps content width on a wide window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(
      tester,
      AppDetailScaffoldWidget(
        title: 'Settings',
        body: Container(key: const Key('body')),
      ),
    );

    expect(tester.getSize(find.byKey(const Key('body'))).width, lessThanOrEqualTo(640));
  });
}
