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

  // ── page — desktop (1280x800 surface, light + dark) ──
  // Full desktop chats view via the shell: window titlebar + rail (with the account
  // avatar) + list pane + no-selection thread pane.
  goldenTestDesktop('chats_list_page', () => const TabBarShell());
}
