import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/shell/app_panel_header_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  group('AppPanelHeaderWidget', () {
    testWidgets('renders the title and the trailing close button', (tester) async {
      await pumpApp(tester, AppPanelHeaderWidget(title: 'Chat details', onClose: () {}));

      expect(find.text('Chat details'), findsOneWidget);
      // The trailing close button is tooltipped with the localized `Close` copy.
      expect(find.byTooltip(l10nEn.actionClose), findsOneWidget);
    });

    testWidgets('invokes onClose when the trailing close button is tapped', (tester) async {
      var closeCount = 0;
      await pumpApp(tester, AppPanelHeaderWidget(title: 'Chat details', onClose: () => closeCount++));

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      expect(closeCount, 1);
    });

    testWidgets('clips a long title to a single ellipsized line', (tester) async {
      const longTitle = 'A very long panel title that will overflow the available header width and must be truncated';
      await pumpApp(tester, const AppPanelHeaderWidget(title: longTitle, onClose: _noop));

      final title = tester.widget<Text>(find.text(longTitle));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
    });
  });
}

void _noop() {}
