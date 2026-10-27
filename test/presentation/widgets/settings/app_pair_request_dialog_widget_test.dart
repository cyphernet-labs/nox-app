import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/device/pair_request.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/settings/app_pair_request_dialog_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  group('AppPairRequestDialogWidget', () {
    for (final (family, word) in [
      (DevicePlatform.ios, l10nEn.devicePlatformIos),
      (DevicePlatform.android, l10nEn.devicePlatformAndroid),
      (DevicePlatform.macos, l10nEn.devicePlatformMacos),
      (DevicePlatform.windows, l10nEn.devicePlatformWindows),
      (DevicePlatform.linux, l10nEn.devicePlatformLinux),
      (DevicePlatform.unknown, l10nEn.devicePlatformUnknown),
    ]) {
      testWidgets('names a ${family.name} device with the app\'s own word for it', (tester) async {
        await pumpApp(
          tester,
          Center(
            child: AppPairRequestDialogWidget(platform: family, onAnswer: (_) {}),
          ),
        );

        expect(find.text(l10nEn.pairRequestMessage(word)), findsOneWidget);
      });
    }

    testWidgets('Allow and Deny each send their answer', (tester) async {
      final answers = <bool>[];
      await pumpApp(
        tester,
        Center(
          child: AppPairRequestDialogWidget(platform: DevicePlatform.windows, onAnswer: answers.add),
        ),
      );

      await tester.tap(find.widgetWithText(TextButton, l10nEn.pairRequestDeny));
      await tester.tap(find.widgetWithText(TextButton, l10nEn.pairRequestAllow));

      expect(answers, [false, true]);
    });

    testWidgets('while an answer is on its way, the button pressed turns and neither can be pressed', (tester) async {
      await pumpApp(
        tester,
        Center(
          child: AppPairRequestDialogWidget(platform: DevicePlatform.windows, answering: true, onAnswer: (_) {}),
        ),
        settle: false,
      );

      expect(find.text(l10nEn.pairRequestAllow), findsNothing, reason: 'Allow turns into a spinner');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, l10nEn.pairRequestDeny)).onPressed, isNull);
    });

    testWidgets('a failed answer is said under the question', (tester) async {
      await pumpApp(
        tester,
        Center(
          child: AppPairRequestDialogWidget(platform: DevicePlatform.windows, failed: true, onAnswer: (_) {}),
        ),
      );

      expect(find.text(l10nEn.pairRequestAnswerError), findsOneWidget);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, l10nEn.pairRequestAllow)).onPressed, isNotNull);
    });

    testWidgets('with nothing left to answer, neither button can be pressed', (tester) async {
      await pumpApp(tester, const Center(child: AppPairRequestDialogWidget(platform: DevicePlatform.windows)));

      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, l10nEn.pairRequestAllow)).onPressed, isNull);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, l10nEn.pairRequestDeny)).onPressed, isNull);
    });

    testWidgets('large text still fits (FR-016)', (tester) async {
      await pumpApp(
        tester,
        Center(
          child: AppPairRequestDialogWidget(platform: DevicePlatform.ios, failed: true, onAnswer: (_) {}),
        ),
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
