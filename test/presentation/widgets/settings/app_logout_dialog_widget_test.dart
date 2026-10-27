import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/settings/app_logout_dialog_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  group('AppLogoutDialogWidget', () {
    testWidgets('Cancel resolves to cancelled', (tester) async {
      LogoutDialogResult? result;
      await pumpApp(
        tester,
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(onPressed: () async => result = await AppLogoutDialogWidget.show(context), child: const Text('open')),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.logoutDialogTitle), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, l10nEn.actionCancel));
      await tester.pumpAndSettle();

      expect(result, LogoutDialogResult.cancelled);
    });

    testWidgets('Confirm keeps the dialog with a spinner until the logout has gone through', (tester) async {
      final logout = Completer<bool>();
      LogoutDialogResult? result;
      await pumpApp(
        tester,
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async => result = await AppLogoutDialogWidget.show(context, logout: () => logout.future),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, l10nEn.logoutRow));
      await tester.pump(const Duration(seconds: 1)); // the wipe is still running
      expect(find.descendant(of: find.byType(TextButton), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(find.text(l10nEn.logoutDialogTitle), findsOneWidget, reason: 'modal until the logout is done');
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, l10nEn.actionCancel)).onPressed, isNull);

      logout.complete(true);
      await tester.pumpAndSettle();
      expect(result, LogoutDialogResult.done);
      expect(find.text(l10nEn.logoutDialogTitle), findsNothing);
    });

    testWidgets('a logout that did not go through closes the dialog as failed', (tester) async {
      LogoutDialogResult? result;
      await pumpApp(
        tester,
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async => result = await AppLogoutDialogWidget.show(context, logout: () async => false),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, l10nEn.logoutRow));
      await tester.pumpAndSettle();

      expect(result, LogoutDialogResult.failed);
    });

    testWidgets('a dialog that came up over it during the logout stays, and only the logout dialog closes', (tester) async {
      final logout = Completer<bool>();
      LogoutDialogResult? result;
      late BuildContext appContext;
      await pumpApp(
        tester,
        Builder(
          builder: (context) {
            appContext = context;
            return Center(
              child: ElevatedButton(
                onPressed: () async => result = await AppLogoutDialogWidget.show(context, logout: () => logout.future),
                child: const Text('open'),
              ),
            );
          },
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, l10nEn.logoutRow));
      await tester.pump();
      // The request dialog 8.2 comes up over it while the logout runs.
      unawaited(
        showDialog<void>(
          context: appContext,
          builder: (_) => const AlertDialog(title: Text('A new device asks to join')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500)); // the spinner keeps animating: no settle here

      logout.complete(false);
      await tester.pumpAndSettle();

      expect(result, LogoutDialogResult.failed);
      expect(find.text(l10nEn.logoutDialogTitle), findsNothing, reason: 'the logout dialog closed itself');
      expect(find.text('A new device asks to join'), findsOneWidget, reason: 'and nothing else');
    });

    testWidgets('with nothing to run (the gallery) confirming answers done at once', (tester) async {
      LogoutDialogResult? result;
      await pumpApp(
        tester,
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(onPressed: () async => result = await AppLogoutDialogWidget.show(context), child: const Text('open')),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, l10nEn.logoutRow));
      await tester.pumpAndSettle();

      expect(result, LogoutDialogResult.done);
    });
  });
}
