@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/presentation/pages/chats_list_page/bloc/chats_list_bloc.dart';
import 'package:nox_app/presentation/pages/chats_list_page/chats_list_page.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';

import '../../../utils/golden.dart';

// Goldens for the Chats list (5.1) in both categories: page-mobile (the screen on
// the 360 surface) and page-desktop (the full desktop view rendered through the
// TabBarShell so the rail + window titlebar + account avatar are part of the
// baseline). Functional states are seeded via ChatsListPage.initialScenario.
//
// The interaction-only states are locked by behavioral widget tests in
// chats_list_page_test.dart rather than goldens: 'search filters …' / 'search with
// no match …' cover the search/search-empty states, and 'desktop selection fills the
// row …' asserts the selected-row fill swap (secondaryContainer vs transparent).
void main() {
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  // ── page — mobile (360 surface, light + dark) ──
  goldenTest('chats_list_page', () => const ChatsListPage(inShell: true));
  goldenTest('chats_list_page_empty', () => const ChatsListPage(inShell: true, initialScenario: ChatsListScenario.empty));
  goldenTest('chats_list_page_offline', () => const ChatsListPage(inShell: true, initialScenario: ChatsListScenario.offline));
  goldenTest('chats_list_page_inline_error', () => const ChatsListPage(inShell: true, initialScenario: ChatsListScenario.inlineError));
  goldenTest('chats_list_page_error', () => const ChatsListPage(inShell: true, initialScenario: ChatsListScenario.fatal));

  // The ONLY page-level baseline that contains a chat row with a badge, and the
  // badge is produced by the real mechanism - a chat is opened, so a read mark
  // exists, and messages then arrive above it. Without this, nothing at page
  // level covers unread emphasis at all; the widget baselines feed their
  // numbers from literals and never touch the recount.
  goldenTest('chats_list_page_unread', () => const ChatsListPage(inShell: true, initialScenario: ChatsListScenario.unread));

  // ── page — desktop (1280x800 surface, light + dark) ──
  // Full desktop chats view via the shell: window titlebar + rail (with the account
  // avatar) + list pane + no-selection thread pane.
  goldenTestDesktop('chats_list_page', () => const TabBarShell());

  // Constitution VI: the wide branch renders the badge differently and must be
  // locked too. Same scenario, desktop surface.
  goldenTestDesktop('chats_list_page_unread', () => const ChatsListPage(inShell: false, initialScenario: ChatsListScenario.unread));
}
