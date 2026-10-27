import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/presentation/pages/chats_list_page/chats_list_page.dart';
import 'package:nox_app/presentation/widgets/chat/app_chat_item_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_thread_view_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_list_detail_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/pump_app.dart';

/// Desktop (`_wide`) parity for the reactive chats list (analyze C1 / FR-011 / SC-006):
/// the list-detail renders the reactive list, and selecting a chat opens its thread in the
/// detail pane (the per-story bloc tests are layout-agnostic; this locks the wide surface).
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> settle(WidgetTester tester) async {
    // Bounded pumps (not pumpAndSettle) — the reactive DB subscriptions + mock delays keep
    // async work in flight, which pumpAndSettle would wait on indefinitely.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('the _wide list-detail renders the reactive list and selecting a chat opens its thread in the pane', (tester) async {
    await pumpApp(tester, const ChatsListPage(inShell: true, forceWide: true), settle: false);
    await settle(tester); // list loads + reactive refresh settles

    expect(find.byType(AppListDetailWidget), findsOneWidget); // desktop list-detail layout
    expect(find.byType(AppChatItemWidget), findsWidgets); // reactive rows rendered

    await tester.tap(find.byType(AppChatItemWidget).first);
    await settle(tester);

    // Selecting a chat shows its thread in the detail pane (no push), retained on refresh.
    expect(find.byType(AppThreadViewWidget), findsOneWidget);
    expect(find.byType(AppListDetailWidget), findsOneWidget);
  });
}
