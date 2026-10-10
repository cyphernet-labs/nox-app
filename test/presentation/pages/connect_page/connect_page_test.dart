import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/pairing_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/connection/connection_problem.dart';
import 'package:nox_app/domain/model/connection/connection_settings.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/connect_page/bloc/connect_bloc.dart';
import 'package:nox_app/presentation/pages/connect_page/connect_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/pump_app.dart';
import 'bloc/connect_bloc_test.mocks.dart';

final l10nEn = AppLocalizationsEn();

/// A link with one direct address and nothing else (the contract's `minimal`
/// vector).
const String _link = 'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7';

/// The connection screen (phase 045, FR-013) on both widths: what it shows,
/// what it refuses, and the way back.
void main() {
  late MockAuthRepository auth;
  late StreamController<bool> approval;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    provideDummy<RepositoryResult<bool>>(const RepositoryResult.success(data: true));
    auth = MockAuthRepository();
    approval = StreamController<bool>.broadcast();
    addTearDown(approval.close);
    when(auth.watchAwaitingApproval()).thenAnswer((_) => approval.stream);
    when(auth.cancelPairing()).thenAnswer((_) async {});
    getIt.allowReassignment = true;
    getIt.registerSingleton<AuthRepository>(auth);
  });

  tearDown(() async => getIt.reset());

  Future<void> pumpAt(WidgetTester tester, Size size, {ConnectState? initialState}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(tester, ConnectPage(link: _link, initialState: initialState));
  }

  Finder connectButton() => find.widgetWithText(FilledButton, l10nEn.connectAction);

  for (final (width, size) in [('phone', const Size(420, 900)), ('desktop', const Size(1200, 900))]) {
    testWidgets('on a $width: the heading, the link\'s address, an empty onion field, Use Tor off, Connect and Cancel', (tester) async {
      await pumpAt(tester, size);

      expect(find.text(l10nEn.connectTitle), findsOneWidget);
      expect(find.text('192.168.1.20:8443'), findsOneWidget);
      expect(find.text(l10nEn.connectOnionAddressHint), findsOneWidget, reason: 'the empty onion field says it is optional');
      expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isFalse);
      expect(find.text(l10nEn.connectUseTorCaption), findsOneWidget);
      expect(connectButton(), findsOneWidget);
      expect(find.widgetWithText(TextButton, l10nEn.actionCancel), findsOneWidget);
    });
  }

  testWidgets('the server key the link names is shown nowhere', (tester) async {
    await pumpAt(tester, const Size(420, 900));

    final key = PairingLink.parse(_link).serverKeyBase64;
    expect(find.textContaining(key), findsNothing);
    expect(find.textContaining(key.substring(0, 12)), findsNothing);
  });

  testWidgets('Connect pairs with what stands in the fields, Use Tor as ticked', (tester) async {
    when(
      auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection')),
    ).thenAnswer((_) async => const RepositoryResult.success(data: true));
    await pumpAt(tester, const Size(420, 900));

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(connectButton());
    await tester.pump();

    final sent = verify(auth.signIn(identifier: _link, connection: captureAnyNamed('connection'))).captured.single;
    expect(sent, const ConnectionSettings(serverAddress: '192.168.1.20:8443', useTor: true));
  });

  testWidgets('an address that cannot be one is refused at its field when Connect is pressed (US5)', (tester) async {
    await pumpAt(tester, const Size(420, 900));

    await tester.enterText(find.widgetWithText(TextField, l10nEn.connectServerAddressLabel), 'nox.example.org');
    await tester.enterText(find.widgetWithText(TextField, l10nEn.connectOnionAddressLabel), 'example.onion');
    await tester.pump();
    expect(find.text(l10nEn.connectInvalidServerAddress), findsNothing, reason: 'not while typing');

    await tester.tap(connectButton());
    await tester.pump();

    expect(find.text(l10nEn.connectInvalidServerAddress), findsOneWidget);
    expect(find.text(l10nEn.connectionProblemInvalidOnion), findsOneWidget);
    verifyNever(auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection')));
  });

  testWidgets('while a pairing runs, the fields, the checkbox and the way back are locked', (tester) async {
    final answer = Completer<RepositoryResult<bool>>();
    when(auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection'))).thenAnswer((_) => answer.future);
    await pumpAt(tester, const Size(420, 900));

    await tester.tap(connectButton());
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField).first).enabled, isFalse);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged, isNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, l10nEn.actionCancel)).onPressed, isNull);
    expect(find.byWidgetPredicate((w) => w is PopScope && !w.canPop), findsOneWidget, reason: 'no system back either');
    answer.complete(const RepositoryResult.error(exception: RepositoryException.connection));
    await tester.pump();
  });

  testWidgets('why it failed is said under Connect, and Connect can be pressed again', (tester) async {
    await pumpAt(
      tester,
      const Size(420, 900),
      initialState: const ConnectState(
        serverAddress: '192.168.1.20:8443',
        linkServerAddress: '192.168.1.20:8443',
        status: ConnectStatus.failed,
        problem: ConnectionProblem.onionNotFound,
      ),
    );

    expect(find.text(l10nEn.connectionProblemOnionNotFound), findsOneWidget);
    expect(tester.widget<FilledButton>(connectButton()).onPressed, isNotNull);
  });

  testWidgets('with no cause known the failure is the sign-in screen\'s own sentence', (tester) async {
    await pumpAt(
      tester,
      const Size(420, 900),
      initialState: const ConnectState(
        serverAddress: '192.168.1.20:8443',
        linkServerAddress: '192.168.1.20:8443',
        status: ConnectStatus.failed,
      ),
    );

    expect(find.text(l10nEn.loginNetworkError), findsOneWidget);
  });

  for (final (status, text) in [
    (ConnectStatus.linkExpired, l10nEn.loginLinkExpired),
    (ConnectStatus.linkRejected, l10nEn.loginLinkRejected),
  ]) {
    testWidgets('a token refused as ${status.name} says what the sign-in screen said', (tester) async {
      await pumpAt(
        tester,
        const Size(420, 900),
        initialState: ConnectState(serverAddress: '192.168.1.20:8443', linkServerAddress: '192.168.1.20:8443', status: status),
      );

      expect(find.text(text), findsOneWidget);
    });
  }

  testWidgets('Cancel goes back to where the link came from', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(ConnectPage.route(link: _link)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectPage), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, l10nEn.actionCancel));
    await tester.pumpAndSettle();

    expect(find.byType(ConnectPage), findsNothing);
  });

  testWidgets('the back arrow is the app\'s own glyph, named for screen readers', (tester) async {
    await pumpAt(tester, const Size(420, 900));

    expect(find.byTooltip(l10nEn.tooltipBack), findsOneWidget);
  });

  group('an invite that waits for approval (phase 046)', () {
    /// Opens the screen over another and presses Connect on a sign-in that
    /// reports the wait, then holds until [answer].
    Future<void> waitAt(WidgetTester tester, Size size, Completer<RepositoryResult<bool>> answer) async {
      when(auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection'))).thenAnswer((_) async {
        approval.add(true);
        return answer.future;
      });
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(
        tester,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(ConnectPage.route(link: _link)),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(connectButton());
      // The spinner turns for as long as the wait lasts: pumped, not settled.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    for (final (width, size) in [('phone', const Size(420, 900)), ('desktop', const Size(1200, 900))]) {
      testWidgets('on a $width: the fields give way to the wait, with Cancel the one thing to press', (tester) async {
        final answer = Completer<RepositoryResult<bool>>();
        await waitAt(tester, size, answer);

        expect(find.text(l10nEn.connectWaitingApproval), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byType(TextField), findsNothing, reason: 'the fields have done their work');
        expect(connectButton(), findsNothing);
        expect(tester.widget<TextButton>(find.widgetWithText(TextButton, l10nEn.actionCancel)).onPressed, isNotNull);
        answer.complete(const RepositoryResult.error(exception: RepositoryException.connection));
        await tester.pump();
      });
    }

    testWidgets('no way back but Cancel while it waits', (tester) async {
      final answer = Completer<RepositoryResult<bool>>();
      await waitAt(tester, const Size(420, 900), answer);

      expect(find.byWidgetPredicate((w) => w is PopScope && !w.canPop), findsOneWidget);
      final back = find.ancestor(of: find.byTooltip(l10nEn.tooltipBack), matching: find.byType(IconButton));
      expect(tester.widget<IconButton>(back).onPressed, isNull);
      answer.complete(const RepositoryResult.error(exception: RepositoryException.connection));
      await tester.pump();
    });

    testWidgets('Cancel withdraws the request and closes the screen', (tester) async {
      final answer = Completer<RepositoryResult<bool>>();
      when(auth.cancelPairing()).thenAnswer((_) async {
        answer.complete(const RepositoryResult.error(exception: PairingException.cancelled));
      });
      await waitAt(tester, const Size(1200, 900), answer);

      await tester.tap(find.widgetWithText(TextButton, l10nEn.actionCancel));
      await tester.pumpAndSettle();

      verify(auth.cancelPairing()).called(1);
      expect(find.byType(ConnectPage), findsNothing, reason: 'back to where links are entered');
    });

    testWidgets('a Deny is said under Connect, and the way back opens again', (tester) async {
      final answer = Completer<RepositoryResult<bool>>();
      await waitAt(tester, const Size(420, 900), answer);

      answer.complete(const RepositoryResult.error(exception: PairingException.declined));
      await tester.pumpAndSettle();

      expect(find.text(l10nEn.connectDeclined), findsOneWidget);
      expect(find.text(l10nEn.connectWaitingApproval), findsNothing);
      expect(find.byWidgetPredicate((w) => w is PopScope && w.canPop), findsOneWidget);
    });

    testWidgets('no answer in time reads as an expired link', (tester) async {
      final answer = Completer<RepositoryResult<bool>>();
      await waitAt(tester, const Size(420, 900), answer);

      answer.complete(const RepositoryResult.error(exception: RepositoryException.notFound));
      await tester.pumpAndSettle();

      expect(find.text(l10nEn.loginLinkExpired), findsOneWidget);
    });
  });
}
