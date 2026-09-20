import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/settings_root_page/settings_root_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

String r(Rect rect) =>
    '(${rect.left.toStringAsFixed(1)}, ${rect.top.toStringAsFixed(1)}) ${rect.width.toStringAsFixed(1)}x${rect.height.toStringAsFixed(1)}';

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('measure', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final height in <double>[610, 600, 599, 598, 597, 590, 580, 570]) {
      await tester.binding.setSurfaceSize(Size(1280, height));
      await pumpApp(tester, const SettingsRootPage(inShell: true, forceWide: true), settle: false);
      await tester.pump(const Duration(milliseconds: 300));

      debugPrint('=== height $height  exception=${tester.takeException()}');

      for (final label in <String>[
        l10nEn.settingsAccountTitle,
        l10nEn.settingsDevicesTitle,
        l10nEn.settingsNotificationsTitle,
        l10nEn.settingsAppearanceTitle,
        l10nEn.settingsLanguageTitle,
        l10nEn.settingsTermsTitle,
        l10nEn.settingsAboutTitle,
        l10nEn.logoutRow,
      ]) {
        final finder = find.text(label);
        if (finder.evaluate().isEmpty) {
          debugPrint('  $label: ABSENT');
          continue;
        }
        // Restrict to the menu pane (x < 340).
        final rects = finder.evaluate().map((e) {
          final ro = e.renderObject! as RenderBox;
          final topLeft = ro.localToGlobal(Offset.zero);
          return topLeft & ro.size;
        }).toList();
        debugPrint('  $label: ${rects.map(r).join(' | ')}');
      }

      // The group containers (bottom border) inside the menu pane.
      final groups = find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).border != null,
      );
      for (final e in groups.evaluate()) {
        final ro = e.renderObject! as RenderBox;
        final topLeft = ro.localToGlobal(Offset.zero);
        if (topLeft.dx > 400) continue;
        debugPrint('  GROUP: ${r(topLeft & ro.size)}');
      }

      final scrolls = find.byType(SingleChildScrollView);
      for (final e in scrolls.evaluate()) {
        final ro = e.renderObject! as RenderBox;
        final topLeft = ro.localToGlobal(Offset.zero);
        if (topLeft.dx > 400) continue;
        final state = tester.state<ScrollableState>(find.descendant(of: find.byWidget(e.widget), matching: find.byType(Scrollable)));
        debugPrint(
          '  SCROLLVIEW: ${r(topLeft & ro.size)} maxExtent=${state.position.maxScrollExtent.toStringAsFixed(1)} '
          'viewport=${state.position.viewportDimension.toStringAsFixed(1)}',
        );
      }
    }
  });
}
