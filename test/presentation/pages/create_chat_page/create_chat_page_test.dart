import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/create_chat_page/create_chat_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  // The create form's uniqueness check now reads the DB via chatRepository (D4), so
  // the bloc needs the test-env DI (was DI-less when the check was a frozen set).
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
  });

  tearDown(() async {
    await getIt.reset();
  });

  Finder createButton() => find.widgetWithText(FilledButton, l10nEn.actionCreate);

  testWidgets('mobile: empty disables Create, a free name enables it', (tester) async {
    await pumpApp(tester, const CreateChatPage(), settle: false);

    expect(tester.widget<FilledButton>(createButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Fresh chat');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(tester.widget<FilledButton>(createButton()).onPressed, isNotNull);
  });

  testWidgets('mobile: a taken name shows the taken error', (tester) async {
    await pumpApp(tester, const CreateChatPage(), settle: false);

    await tester.enterText(find.byType(TextField), 'General');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text(l10nEn.nameTakenError), findsOneWidget);
  });

  testWidgets('desktop: renders a modal Dialog with Cancel and Create', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpApp(tester, const CreateChatPage(dialog: true), settle: false);

    expect(find.byType(Dialog), findsOneWidget); // a real Dialog body (N5), not a simulated scrim
    expect(find.widgetWithText(TextButton, l10nEn.actionCancel), findsOneWidget);
    expect(find.widgetWithText(FilledButton, l10nEn.actionCreate), findsOneWidget);
  });

  // The real desktop production entry point (N5): drive showAsDialog end-to-end so the
  // modal, its result contract (null on cancel / ChatModel on create), and the barrier
  // are exercised — not just the bare Dialog widget.
  Future<(WidgetTester, ValueNotifier<ChatModel?>, ValueNotifier<bool>)> openDialog(WidgetTester tester) async {
    final result = ValueNotifier<ChatModel?>(null);
    final resolved = ValueNotifier<bool>(false);
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              result.value = await CreateChatPage.showAsDialog(context);
              resolved.value = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
      settle: false,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget); // the modal is up
    return (tester, result, resolved);
  }

  testWidgets('showAsDialog resolves with null when Cancel is tapped', (tester) async {
    final (_, result, resolved) = await openDialog(tester);

    await tester.tap(find.widgetWithText(TextButton, l10nEn.actionCancel));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing); // dismissed
    expect(resolved.value, isTrue);
    expect(result.value, isNull);
  });

  testWidgets('showAsDialog resolves with the created ChatModel when Create is tapped', (tester) async {
    final (_, result, resolved) = await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'Dialog-made chat');
    await tester.pump(const Duration(milliseconds: 700)); // debounced uniqueness → valid
    await tester.tap(createButton());
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing); // dialog closed on success
    expect(resolved.value, isTrue);
    expect(result.value, isNotNull);
    expect(result.value!.name, 'Dialog-made chat'); // the created chat flows back to the caller
  });
}
