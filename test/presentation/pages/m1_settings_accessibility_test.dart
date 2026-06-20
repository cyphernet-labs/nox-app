import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/settings/app_info_banner_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_switch_row_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_theme_option_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_detail_scaffold_widget.dart';

import '../../utils/pump_app.dart';

/// Accessibility checks (FR-016) for the M1 settings surface: tap targets >= 48x48
/// and layout survives textScaler up to 2.0.
void main() {
  group('M1 settings accessibility (FR-016)', () {
    testWidgets('detail-scaffold back button is >= 48x48 with a tooltip', (tester) async {
      await pumpApp(tester, const AppDetailScaffoldWidget(title: 'Settings', body: SizedBox.shrink()));

      expect(find.byTooltip(TextConstants.tooltipBack), findsOneWidget);
      final size = tester.getSize(find.byType(IconButton));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('settings widgets survive textScaler 2.0 without overflow', (tester) async {
      await pumpApp(
        tester,
        AppThemeOptionWidget(
          label: 'System (follows the device theme)',
          preview: const SizedBox(width: 48, height: 36),
          selected: true,
          onTap: () {},
        ),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);

      await pumpApp(
        tester,
        const AppSettingsSwitchRowWidget(
          title: 'Push notifications',
          supportingText: 'A longer supporting line that should wrap at a large text scale',
          value: true,
          onChanged: null,
        ),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);

      await pumpApp(
        tester,
        AppInfoBannerWidget(
          icon: NoxIcons.error,
          message: 'A long banner message that should wrap and still fit at a large text scale',
          actionLabel: TextConstants.actionOpenSettings,
          onAction: () {},
        ),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
