import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/chat/rename_chat_dialog/app_rename_chat_dialog_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../utils/pump_app.dart';
import 'app_rename_chat_dialog_widget_test.mocks.dart';

final l10nEn = AppLocalizationsEn();

/// The rename dialog in isolation over a MOCK ChatRepository (a real Sembast repo does
/// not resolve reliably inside testWidgets' fake_async). Hosted behind a plain button so
/// no card/thread live streams are involved; bounded pumps because the autofocused field
/// blinks its cursor forever.
@GenerateMocks([ChatRepository])
void main() {
  late MockChatRepository repo;

  ChatModel renamed(String name) => ChatModel(id: 'chat_0', name: name, lastMessagePreview: '', lastMessageAt: DateTime(2024, 1, 1));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    provideDummy<RepositoryResult<bool>>(const RepositoryResult<bool>.success(data: false));
    provideDummy<RepositoryResult<ChatModel>>(const RepositoryResult<ChatModel>.error(exception: RepositoryException.unknown));
    repo = MockChatRepository();
    // Default: every name is free, every rename succeeds.
    when(
      repo.isChatNameTaken(name: anyNamed('name'), excludeChatId: anyNamed('excludeChatId')),
    ).thenAnswer((_) async => const RepositoryResult<bool>.success(data: false));
    when(
      repo.updateChatName(chatId: anyNamed('chatId'), name: anyNamed('name')),
    ).thenAnswer((invocation) async => RepositoryResult<ChatModel>.success(data: renamed(invocation.namedArguments[#name] as String)));
    getIt.allowReassignment = true;
    getIt.registerSingleton<ChatRepository>(repo);
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> drain(WidgetTester tester, [int steps = 6]) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// Pumps a host whose button opens the rename dialog; returns a getter for the resolved
  /// result (null until the dialog closes).
  Future<bool? Function()> openDialog(WidgetTester tester) async {
    bool? result;
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async => result = await AppRenameChatDialogWidget.show(context, chatId: 'chat_0', currentName: 'Design crit'),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await drain(tester, 3);
    return () => result;
  }

  testWidgets('opens prefilled with the current name; Save is disabled until it changes', (tester) async {
    await openDialog(tester);

    expect(find.text(l10nEn.renameChatTitle), findsOneWidget);
    expect(find.text('Design crit'), findsOneWidget); // prefilled field
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, l10nEn.actionSave)).onPressed, isNull);
  });

  testWidgets('a valid rename saves via updateChatName and resolves true', (tester) async {
    final result = await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'Fresh Name');
    await drain(tester); // debounced uniqueness check → valid + submittable
    await tester.tap(find.widgetWithText(FilledButton, l10nEn.actionSave));
    await drain(tester); // save + dialog close

    verify(repo.updateChatName(chatId: 'chat_0', name: 'Fresh Name')).called(1);
    expect(result(), isTrue);
    expect(find.text(l10nEn.renameChatTitle), findsNothing); // dialog closed
  });

  testWidgets('a taken name blocks Save and shows the taken error', (tester) async {
    when(
      repo.isChatNameTaken(name: 'Occupied', excludeChatId: anyNamed('excludeChatId')),
    ).thenAnswer((_) async => const RepositoryResult<bool>.success(data: true));

    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'Occupied');
    await drain(tester);

    expect(find.text(l10nEn.nameTakenError), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, l10nEn.actionSave)).onPressed, isNull);
    verifyNever(repo.updateChatName(chatId: anyNamed('chatId'), name: anyNamed('name')));
  });

  testWidgets('Cancel dismisses without saving', (tester) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'Discarded');
    await drain(tester);
    await tester.tap(find.widgetWithText(TextButton, l10nEn.actionCancel));
    await drain(tester, 3);

    expect(find.text(l10nEn.renameChatTitle), findsNothing);
    verifyNever(repo.updateChatName(chatId: anyNamed('chatId'), name: anyNamed('name')));
  });
}
