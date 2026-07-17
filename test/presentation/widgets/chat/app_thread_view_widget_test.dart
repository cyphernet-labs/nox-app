import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/general/identity_mock_data.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart';
import 'package:nox_app/presentation/widgets/chat/app_author_header_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_date_separator_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_message_bubble_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_system_line_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_thread_view_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_empty_content_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_error_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_notice_strip_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

// A single fixed chat id so the mock repository seeds one deterministic history
// (14 messages: 1 system line + 13 bubbles) that every test in the file reads.
ChatModel _sampleChat() =>
    ChatModel(id: 'chat_thread_view', name: 'Design crit', lastMessagePreview: '', lastMessageAt: DateTime(2024, 1, 1));

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

      // Own vs other bubbles: 4 own ('You') + 9 other = 13 message rows.
      final ownBubbles = find.byWidgetPredicate((w) => w is AppMessageBubbleWidget && w.isOwn);
      final otherBubbles = find.byWidgetPredicate((w) => w is AppMessageBubbleWidget && !w.isOwn);
      expect(find.byType(AppMessageBubbleWidget), findsNWidgets(13));
      expect(ownBubbles, findsNWidgets(4));
      expect(otherBubbles, findsNWidgets(9));

      // A date separator is inserted on each day change; the mock history spans multiple days.
      expect(find.byType(AppDateSeparatorWidget), findsAtLeastNWidgets(2));

      // Author headers mark other-author group starts and are never emitted for own messages.
      expect(find.byType(AppAuthorHeaderWidget), findsWidgets);
      expect(find.byWidgetPredicate((w) => w is AppAuthorHeaderWidget && w.label == IdentityMockData.currentLabel), findsNothing);

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
      expect(find.byType(AppErrorWidget), findsOneWidget);
    });
  });
}
