import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/presentation/widgets/primitives/app_avatar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_navigation_rail_widget.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/pump_app.dart';

/// US3 / R4 — the desktop rail account avatar updates LIVE when the label is renamed
/// (feature 015). The shell subscribes to the session's reactive label channel, so a
/// `updateLabel` broadcast reaches the avatar without a restart.
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
    // Bounded pumps (not pumpAndSettle) — the shell's tabs keep reactive DB
    // subscriptions + mock delays in flight, which pumpAndSettle would wait on forever.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('the desktop rail account avatar reflects the session label and updates live on a rename', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800)); // wide → the shell renders the rail
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await getIt<SessionRepository>().saveIdentifier(identifier: 'sess-abc', onboardingComplete: true, label: 'Alice');

    await pumpApp(tester, const TabBarShell(), settle: false);
    await settle(tester); // watchLabel seeds the current label + the tabs settle

    // The rail account avatar carries the session label.
    expect(find.byType(AppNavigationRailWidget), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is AppAvatarWidget && w.name == 'Alice'), findsOneWidget);

    // A rename broadcasts live — the avatar updates in the same session, no restart.
    await getIt<SessionRepository>().updateLabel(label: 'Zed');
    await settle(tester);

    expect(find.byWidgetPredicate((w) => w is AppAvatarWidget && w.name == 'Zed'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is AppAvatarWidget && w.name == 'Alice'), findsNothing);
  });
}
