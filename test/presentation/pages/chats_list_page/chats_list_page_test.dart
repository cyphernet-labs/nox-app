import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/chat_thread_page.dart';
import 'package:nox_app/presentation/pages/chats_list_page/chats_list_page.dart';
import 'package:nox_app/presentation/widgets/chat/app_chat_item_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_search_field_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_thread_view_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_list_detail_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_wordmark_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  group('ChatsListPage (mobile)', () {
    Future<void> pumpMobile(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const ChatsListPage());
      // The list now fetches its page on every open (read-through), so the test
      // has to wait out the mock's latency the way it would a real server's.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300)); // the thread fetches on open
      await tester.pumpAndSettle();
    }

    testWidgets('shows the NOX wordmark, the search field and chat rows', (tester) async {
      await pumpMobile(tester);

      expect(find.byType(AppWordmarkWidget), findsWidgets);
      expect(find.byType(AppSearchFieldWidget), findsOneWidget);
      expect(find.byType(AppChatItemWidget), findsWidgets);
    });

    testWidgets('tapping a chat opens the real chat thread (5.2)', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.byType(AppChatItemWidget).first);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300)); // the thread fetches on open
      await tester.pumpAndSettle();

      expect(find.byType(ChatThreadPage), findsOneWidget);
    });

    testWidgets('search filters the list by chat name', (tester) async {
      await pumpMobile(tester);

      await tester.enterText(find.byType(AppSearchFieldWidget), 'Design');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300)); // the thread fetches on open
      await tester.pumpAndSettle();

      expect(find.text('Design crit'), findsOneWidget);
      expect(find.text('NOX core'), findsNothing);
    });

    testWidgets('search with no match shows the empty result text', (tester) async {
      await pumpMobile(tester);

      await tester.enterText(find.byType(AppSearchFieldWidget), 'zzzznomatch');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300)); // the thread fetches on open
      await tester.pumpAndSettle();

      expect(find.text(l10nEn.chatsSearchEmpty), findsOneWidget);
      expect(find.byType(AppChatItemWidget), findsNothing);
    });

    testWidgets('mobile account affordance (N4): the app-bar avatar appears and taps through to onAccount', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var accountTaps = 0;
      await pumpApp(tester, ChatsListPage(inShell: true, accountLabel: 'Aria Vale', onAccount: () => accountTaps++));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300)); // the thread fetches on open
      await tester.pumpAndSettle();

      // The avatar renders in the app bar (tooltip = the Account section title).
      final avatar = find.byTooltip(l10nEn.settingsAccountTitle);
      expect(avatar, findsOneWidget);

      await tester.tap(avatar);
      await tester.pump();
      expect(accountTaps, 1); // hands off to the shell (switch to Settings + jump to Account)
    });

    testWidgets('mobile account affordance is absent when the shell supplies no account identity', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const ChatsListPage(inShell: true)); // no accountLabel/onAccount
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300)); // the thread fetches on open
      await tester.pumpAndSettle();

      expect(find.byTooltip(l10nEn.settingsAccountTitle), findsNothing);
    });
  });

  group('ChatsListPage (desktop)', () {
    Future<void> pumpDesktop(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const ChatsListPage());
      // The list now fetches its page on every open (read-through), so the test
      // has to wait out the mock's latency the way it would a real server's.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300)); // the thread fetches on open
      await tester.pumpAndSettle();
    }

    testWidgets('renders the list-detail with a no-selection placeholder', (tester) async {
      await pumpDesktop(tester);

      expect(find.byType(AppListDetailWidget), findsOneWidget);
      expect(find.text(l10nEn.chatsNoSelectionTitle), findsOneWidget);
    });

    testWidgets('selecting a row loads the real thread pane without a push', (tester) async {
      await pumpDesktop(tester);

      await tester.tap(find.byType(AppChatItemWidget).first);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300)); // the thread fetches on open
      await tester.pumpAndSettle();

      // No-selection placeholder is gone (the thread pane swapped) and no push happened.
      expect(find.text(l10nEn.chatsNoSelectionTitle), findsNothing);
      expect(find.byType(ChatsListPage), findsOneWidget);
      expect(find.byType(ChatThreadPage), findsNothing); // pane swap, not a push
      expect(find.byType(AppThreadViewWidget), findsOneWidget);
    });

    testWidgets('desktop selection fills the row with secondaryContainer', (tester) async {
      await pumpDesktop(tester);

      await tester.tap(find.byType(AppChatItemWidget).first);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300)); // the thread fetches on open
      await tester.pumpAndSettle();

      final scheme = Theme.of(tester.element(find.byType(AppChatItemWidget).first)).colorScheme;
      Material rowMaterial(int i) =>
          tester.widget<Material>(find.ancestor(of: find.byType(AppChatItemWidget).at(i), matching: find.byType(Material)).first);

      expect(rowMaterial(0).color, scheme.secondaryContainer); // selected row is filled
      expect(rowMaterial(1).color, Colors.transparent); // a sibling row stays transparent
    });
  });
}
