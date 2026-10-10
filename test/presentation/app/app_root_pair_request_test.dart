import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/device/pair_request.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/app/app_root.dart';
import 'package:nox_app/presentation/pages/login_page/login_page.dart';
import 'package:nox_app/presentation/widgets/settings/app_pair_request_dialog_widget.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/fake_pair_request_service.dart';

final l10nEn = AppLocalizationsEn();

/// The question a device is asked when a new device presents an invite it
/// issued (phase 046, FR-008): over whatever screen is up, on both widths,
/// for as long as the request waits.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePairRequestService requests;
  const windows = PairRequest(requestId: 'r_1', platform: DevicePlatform.windows);
  const ipad = PairRequest(requestId: 'r_2', platform: DevicePlatform.ios);

  Future<void> signedIn({bool paired = true}) async {
    FlutterSecureStorage.setMockInitialValues(paired ? {'session.identifier': 'registered'} : {});
    SharedPreferences.setMockInitialValues(paired ? {'session.onboarding_complete': true} : {});
    await configureDependencies(Environment.test);
    await getIt.allReady();
    requests = registerFakePairRequests();
  }

  tearDown(() async {
    await requests.close();
    await getIt.reset();
  });

  /// The app on a window [size] wide, settled on its first screen.
  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(const AppRoot());
    await tester.pumpAndSettle();
  }

  Finder question(String family) => find.text(l10nEn.pairRequestMessage(family));

  for (final (width, size) in [('phone', const Size(420, 900)), ('desktop', const Size(1280, 800))]) {
    testWidgets('on a $width: a new device is asked about over the screen that is up, and Allow lets it in', (tester) async {
      await signedIn();
      await open(tester, size);
      expect(find.byType(TabBarShell), findsOneWidget);

      requests.ask(windows);
      await tester.pumpAndSettle();

      expect(question(l10nEn.devicePlatformWindows), findsOneWidget);
      expect(find.byType(TabBarShell), findsOneWidget, reason: 'over the screen, not in place of it');

      await tester.tap(find.widgetWithText(TextButton, l10nEn.pairRequestAllow));
      await tester.pumpAndSettle();

      expect(requests.answers, [(requestId: 'r_1', allow: true)]);
      expect(find.byType(AppPairRequestDialogWidget), findsNothing, reason: 'answered, the question is over');
    });
  }

  testWidgets('Deny answers no', (tester) async {
    await signedIn();
    await open(tester, const Size(420, 900));
    requests.ask(windows);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, l10nEn.pairRequestDeny));
    await tester.pumpAndSettle();

    expect(requests.answers, [(requestId: 'r_1', allow: false)]);
    expect(find.byType(AppPairRequestDialogWidget), findsNothing);
  });

  testWidgets('a request that closes elsewhere - its time, the new device\'s Cancel - takes the dialog with it', (tester) async {
    await signedIn();
    await open(tester, const Size(420, 900));
    requests.ask(windows);
    await tester.pumpAndSettle();
    expect(find.byType(AppPairRequestDialogWidget), findsOneWidget);

    requests.resolve('r_1');
    await tester.pumpAndSettle();

    expect(find.byType(AppPairRequestDialogWidget), findsNothing);
    expect(requests.answers, isEmpty);
  });

  testWidgets('two requests are asked about one after the other', (tester) async {
    await signedIn();
    await open(tester, const Size(1280, 800));
    requests
      ..ask(windows)
      ..ask(ipad);
    await tester.pumpAndSettle();
    expect(question(l10nEn.devicePlatformWindows), findsOneWidget);
    expect(find.byType(AppPairRequestDialogWidget), findsOneWidget, reason: 'one question at a time');

    await tester.tap(find.widgetWithText(TextButton, l10nEn.pairRequestDeny));
    await tester.pumpAndSettle();

    expect(question(l10nEn.devicePlatformIos), findsOneWidget);
  });

  // The SAME route has to stay up: AppRoot asks again about a request whose
  // dialog something else closed, so "a dialog is there" would hold even if
  // back closed it and it came straight back.
  ModalRoute<Object?> dialogRoute(WidgetTester tester) => ModalRoute.of(tester.element(find.byType(AppPairRequestDialogWidget)))!;

  testWidgets('the question cannot be put aside unanswered: back and the scrim do nothing', (tester) async {
    await signedIn();
    await open(tester, const Size(420, 900));
    requests.ask(windows);
    await tester.pumpAndSettle();
    final route = dialogRoute(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(identical(dialogRoute(tester), route), isTrue, reason: 'back closed the question, and it was asked again');
    expect(route.isCurrent, isTrue);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(identical(dialogRoute(tester), route), isTrue, reason: 'the scrim closed the question');
  });

  testWidgets('on a desktop Escape does nothing either', (tester) async {
    await signedIn();
    await open(tester, const Size(1280, 800));
    requests.ask(windows);
    await tester.pumpAndSettle();
    final route = dialogRoute(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(identical(dialogRoute(tester), route), isTrue, reason: 'Escape closed the question');
  });

  testWidgets('an answer that did not get through says so, and both buttons stay', (tester) async {
    await signedIn();
    requests.reply = (_, _) async => const RepositoryResult<bool>.error(exception: RepositoryException.internal);
    await open(tester, const Size(420, 900));
    requests.ask(windows);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, l10nEn.pairRequestAllow));
    await tester.pumpAndSettle();

    expect(find.text(l10nEn.pairRequestAnswerError), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, l10nEn.pairRequestAllow)).onPressed, isNotNull);
  });

  testWidgets('nothing is asked over the sign-in screen: only a paired device issues invites', (tester) async {
    await signedIn(paired: false);
    await open(tester, const Size(420, 900));
    expect(find.byType(LoginPage), findsOneWidget);

    requests.ask(windows);
    await tester.pumpAndSettle();

    expect(find.byType(AppPairRequestDialogWidget), findsNothing);
  });
}
