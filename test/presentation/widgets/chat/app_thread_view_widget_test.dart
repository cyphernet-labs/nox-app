import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/entity/chat/chat_entity.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/chat_creation.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart';
import 'package:nox_app/presentation/widgets/chat/app_author_header_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_date_separator_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_message_bubble_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_system_line_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_thread_view_widget.dart';
import 'package:nox_app/presentation/widgets/chat/rename_chat_dialog/app_rename_chat_dialog_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_empty_content_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_error_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_notice_strip_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

// A single fixed chat id so the mock repository seeds one deterministic history
// (14 messages: 1 system line + 13 bubbles) that every test in the file reads.
ChatModel _sampleChat() => ChatModel(id: 'chat_3', name: 'Design crit', lastMessagePreview: '', lastMessageAt: DateTime(2024, 1, 1));

// Drive the debug-only ChatThreadScenario dropdown (kDebugMode is true under
// `flutter test`, so `demo: true` renders it).
Future<void> _selectScenario(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButton<ChatThreadScenario>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('scenario: $name').last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async => configureDependencies(Environment.test));
  tearDownAll(() async => getIt.reset());

  group('AppThreadViewWidget', () {
    testWidgets('normal scenario assembles the grouped thread rows', (tester) async {
      // Tall surface so the reverse ListView lays out every row (nothing scrolled off) and counts are exact.
      await tester.binding.setSurfaceSize(const Size(700, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, AppThreadViewWidget(chat: _sampleChat(), demo: true));

      // Leading system line ('Chat created by …') sits at the top of the thread.
      expect(find.byType(AppSystemLineWidget), findsOneWidget);

      // Own vs other bubbles: 4 own + 9 other = 13 message rows (no session in the
      // test env → own-id resolves to the fallback sentinel, matching the seed).
      final ownBubbles = find.byWidgetPredicate((w) => w is AppMessageBubbleWidget && w.isOwn);
      final otherBubbles = find.byWidgetPredicate((w) => w is AppMessageBubbleWidget && !w.isOwn);
      expect(find.byType(AppMessageBubbleWidget), findsNWidgets(13));
      expect(ownBubbles, findsNWidgets(4));
      expect(otherBubbles, findsNWidgets(9));

      // A date separator is inserted on each day change; the mock history spans multiple days.
      expect(find.byType(AppDateSeparatorWidget), findsAtLeastNWidgets(2));

      // Author headers mark other-author group starts and are never emitted for own messages.
      expect(find.byType(AppAuthorHeaderWidget), findsWidgets);
      expect(find.byWidgetPredicate((w) => w is AppAuthorHeaderWidget && w.label == Constants.defaultUserLabel), findsNothing);

      // The error / empty branches are not taken while there is history.
      expect(find.byType(AppErrorWidget), findsNothing);
      expect(find.byType(AppEmptyContentWidget), findsNothing);
    });

    testWidgets('offline scenario surfaces the offline notice strip above the thread', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, AppThreadViewWidget(chat: _sampleChat(), demo: true));

      await _selectScenario(tester, 'offline');

      expect(find.byType(AppNoticeStripWidget), findsOneWidget);
      expect(find.text(l10nEn.noConnection), findsOneWidget);
      // History still renders underneath the offline banner.
      expect(find.byType(AppMessageBubbleWidget), findsWidgets);
    });

    testWidgets('empty scenario renders the empty-content placeholder and no bubbles', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, AppThreadViewWidget(chat: _sampleChat(), demo: true));

      await _selectScenario(tester, 'empty');

      expect(find.byType(AppEmptyContentWidget), findsOneWidget);
      expect(find.text(l10nEn.threadEmptyTitle), findsOneWidget);
      expect(find.byType(AppMessageBubbleWidget), findsNothing);
    });

    testWidgets('fatal scenario renders the error state with a try-again action', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, AppThreadViewWidget(chat: _sampleChat(), demo: true));

      await _selectScenario(tester, 'fatal');

      expect(find.byType(AppErrorWidget), findsOneWidget);
      expect(find.text(l10nEn.actionTryAgain), findsOneWidget);
      // The error branch replaces both the thread and the composer.
      expect(find.byType(AppMessageBubbleWidget), findsNothing);
      expect(find.byType(AppNoticeStripWidget), findsNothing);

      // Try-again re-runs initialize → the fatal scenario short-circuits back to the error state.
      await tester.tap(find.text(l10nEn.actionTryAgain));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300)); // the thread fetches on open
      await tester.pumpAndSettle();
      expect(find.byType(AppErrorWidget), findsOneWidget);
    });
  });

  group('AppThreadViewWidget - a chat not on the server yet (phase 041)', () {
    /// A chat this device created, stored as the queue would leave it.
    Future<ChatModel> storedChat(WidgetTester tester, String id, ChatCreation creation) async {
      final stored = switch (creation) {
        ChatCreation.pending => 'pending',
        ChatCreation.nameTaken => 'name_taken',
        ChatCreation.failed => 'failed',
      };
      await tester.runAsync(
        () => getIt<ChatDao>().upsert(
          ChatEntity(
            id: id,
            name: 'Kitchen',
            lastMessagePreview: '',
            lastMessageAt: DateTime(2024, 1, 1).toIso8601String(),
            unreadCount: 0,
            lastOpenedSeq: null,
            creation: stored,
          ),
        ),
      );
      return ChatModel(id: id, name: 'Kitchen', lastMessagePreview: '', lastMessageAt: DateTime(2024, 1, 1), creation: creation);
    }

    testWidgets('waiting, with nothing to take it there: one notice, and it says why the messages hold', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final chat = await storedChat(tester, 'c_00000000000000000000000000000041', ChatCreation.pending);
      await pumpApp(tester, AppThreadViewWidget(chat: chat, demo: true));

      await _selectScenario(tester, 'offline');

      expect(find.text(l10nEn.chatCreationPendingNotice), findsOneWidget);
      expect(find.text(l10nEn.noConnection), findsNothing, reason: 'one notice, the one that says more');
    });

    testWidgets('waiting, with a current channel: the creation is going out now, and no notice flashes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final chat = await storedChat(tester, 'c_00000000000000000000000000000042', ChatCreation.pending);
      await pumpApp(tester, AppThreadViewWidget(chat: chat));

      expect(find.text(l10nEn.chatCreationPendingNotice), findsNothing);
    });

    testWidgets('a taken name: the notice offers Rename, and Rename opens the rename dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final chat = await storedChat(tester, 'c_00000000000000000000000000000043', ChatCreation.nameTaken);
      await pumpApp(tester, AppThreadViewWidget(chat: chat));

      expect(find.text(l10nEn.chatCreationNameTakenNotice), findsOneWidget);
      await tester.tap(find.text(l10nEn.actionRename));
      await tester.pumpAndSettle();

      expect(find.byType(AppRenameChatDialogWidget), findsOneWidget);
    });

    testWidgets('a refused creation: Try again puts the chat back in line, and the notice goes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const id = 'c_00000000000000000000000000000044';
      final chat = await storedChat(tester, id, ChatCreation.failed);
      await pumpApp(tester, AppThreadViewWidget(chat: chat));
      expect(find.text(l10nEn.chatCreationFailedNotice), findsOneWidget);

      await tester.tap(find.text(l10nEn.actionTryAgain));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600)); // the queue creates it on the mock server
      await tester.pumpAndSettle();

      final stored = await tester.runAsync(() => getIt<ChatDao>().getById(id));
      expect(stored?.creation, isNot('failed'));
      expect(find.text(l10nEn.chatCreationFailedNotice), findsNothing);
    });
  });
}
