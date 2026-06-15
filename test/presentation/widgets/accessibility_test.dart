import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/chat/app_chat_item_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_composer_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_create_fab_widget.dart';

import '../../utils/pump_app.dart';

/// Cross-widget accessibility checks (FR-016): tap targets >= 48x48, icon-only
/// actions expose a tooltip/semantics, and layout survives textScaler up to 2.0.
void main() {
  group('accessibility (FR-016)', () {
    testWidgets('composer icon-action tap targets are >= 48x48', (tester) async {
      await pumpApp(tester, AppComposerWidget(sendActive: true, onSend: () {}, onAttach: () {}));

      final buttons = find.byType(IconButton);
      expect(buttons, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final size = tester.getSize(buttons.at(i));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('create FAB tap target is >= 48x48 with a tooltip', (tester) async {
      await pumpApp(tester, AppCreateFabWidget(onPressed: () {}));

      final size = tester.getSize(find.byType(FloatingActionButton));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(find.byTooltip(TextConstants.tooltipCreateChat), findsOneWidget);
    });

    testWidgets('composer actions expose tooltips/semantics', (tester) async {
      await pumpApp(tester, AppComposerWidget(sendActive: true, onSend: () {}, onAttach: () {}));

      expect(find.byTooltip(TextConstants.tooltipAttachFile), findsOneWidget);
      expect(find.byTooltip(TextConstants.tooltipSend), findsOneWidget);
    });

    testWidgets('layout survives textScaler 2.0 without overflow', (tester) async {
      await pumpApp(
        tester,
        const AppChatItemWidget(
          name: 'A long chat name that should ellipsize',
          preview: 'A long preview line that should also ellipsize',
          time: '09:00',
          unread: 12,
        ),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);

      await pumpApp(tester, const AppComposerWidget(value: 'A long draft that should reflow'), textScale: 2.0);
      expect(tester.takeException(), isNull);
    });
  });
}
