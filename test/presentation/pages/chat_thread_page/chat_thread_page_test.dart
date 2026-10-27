import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/chat_thread_page.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/chat/app_composer_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_invite_seam_action_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_message_bubble_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_thread_header_widget.dart';

import '../../../utils/pump_app.dart';

ChatModel _sampleChat() => ChatModel(id: 'chat_0', name: 'Design crit', lastMessagePreview: '', lastMessageAt: DateTime(2024, 1, 1));

final l10nEn = AppLocalizationsEn();

void main() {
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  group('ChatThreadPage (mobile)', () {
    Future<void> pumpMobile(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, ChatThreadPage(chat: _sampleChat()));
      // The thread fetches its window on open (read-through), so the test has to
      // wait out the mock's latency the way it would a real server's.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300)); // the thread fetches on open
      await tester.pumpAndSettle();
    }

    testWidgets('shows the chat name, message bubbles and the composer', (tester) async {
      await pumpMobile(tester);

      expect(find.text('Design crit'), findsOneWidget);
      expect(find.byType(AppMessageBubbleWidget), findsWidgets);
      expect(find.byType(AppComposerWidget), findsOneWidget);
    });

    testWidgets('the app bar carries the same invite seam the desktop header does', (tester) async {
      // The real page, not a hand-built AppBar: the invariant is that both
      // widths carry this control, and a test that assembles the tree itself
      // proves nothing about the page it is meant to guard.
      await pumpMobile(tester);

      expect(find.byType(AppInviteSeamActionWidget), findsOneWidget);
      final button = tester.widget<IconButton>(
        find.ancestor(of: find.byTooltip(l10nEn.chatInvitePerson), matching: find.byType(IconButton)).first,
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('sending a message appends it to the thread', (tester) async {
      await pumpMobile(tester);

      await tester.enterText(find.byType(TextField), 'Hi from the test');
      await tester.pump();
      await tester.tap(find.byType(IconButton).last); // send
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300)); // the thread fetches on open
      await tester.pumpAndSettle();

      expect(find.text('Hi from the test'), findsOneWidget);
    });
  });

  group('ChatThreadPage (desktop)', () {
    testWidgets('renders the persistent thread header', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, ChatThreadPage(chat: _sampleChat()));
      // The thread fetches its window on open (read-through), so the test has to
      // wait out the mock's latency the way it would a real server's.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300)); // the thread fetches on open
      await tester.pumpAndSettle();

      expect(find.byType(AppThreadHeaderWidget), findsOneWidget);
      expect(find.byType(AppComposerWidget), findsOneWidget);
    });
  });
}
