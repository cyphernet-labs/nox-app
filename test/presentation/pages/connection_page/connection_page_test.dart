import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/connection_problem.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/connection_page/connection_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/fixed_connection_status.dart';
import '../../../utils/fixed_session_phase.dart';
import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

/// Settings > Connection on a phone (phase 045, US4); the desktop pane is
/// covered from the settings root.
void main() {
  late FixedSessionPhaseService phase;
  late FixedConnectionStatusService status;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    getIt.allowReassignment = true;
    phase = FixedSessionPhaseService();
    getIt.registerSingleton<SessionPhaseService>(phase);
    status = FixedConnectionStatusService(FixedConnectionStatusService.direct);
    getIt.registerSingleton<ConnectionStatusService>(status);
    await getIt<SessionRepository>().saveServer(address: '192.168.1.20:8443', serverKey: 'oJql9HpnWYAv+VX43C0qFKXJnSO+l/hkEn/5ODRVpPA=');
  });

  tearDown(() async => getIt.reset());

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(tester, const ConnectionPage());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  Finder saveButton() => find.widgetWithText(FilledButton, l10nEn.actionSave);

  testWidgets('the title, the fields as they stand, Save off, and Use Tor off with its caption', (tester) async {
    await pump(tester);

    expect(find.text(l10nEn.settingsConnectionTitle), findsOneWidget);
    expect(find.text('192.168.1.20:8443'), findsOneWidget);
    expect(find.text(l10nEn.connectOnionAddressHint), findsOneWidget, reason: 'no onion address known, and it says so');
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
    expect(find.text(l10nEn.connectUseTorCaption), findsOneWidget);
  });

  testWidgets('a valid change turns Save on; Save applies it and starts the channel again', (tester) async {
    await pump(tester);

    await tester.enterText(find.widgetWithText(TextField, l10nEn.connectServerAddressLabel), '10.8.0.2:8443');
    await tester.pump();
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNotNull);

    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect((await tester.runAsync(() => getIt<ServerAddressesRepository>().read()))!.data!.manualAddress, '10.8.0.2:8443');
    expect(phase.reconnects, 1);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull, reason: 'nothing left to save');
  });

  testWidgets('an address that cannot be one keeps Save off, and the field says why', (tester) async {
    await pump(tester);

    await tester.enterText(find.widgetWithText(TextField, l10nEn.connectOnionAddressLabel), 'example.onion');
    await tester.pump();

    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    expect(find.text(l10nEn.connectionProblemInvalidOnion), findsOneWidget);
  });

  testWidgets('Use Tor applies the moment it is switched', (tester) async {
    await pump(tester);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    expect((await tester.runAsync(() => getIt<ServerAddressesRepository>().read()))!.data!.useTor, isTrue);
    expect(phase.reconnects, 1);
  });

  testWidgets('while there is no connection the line above the fields says why', (tester) async {
    status.value = const ConnectionStatus(state: LinkState.offline, problem: ConnectionProblem.turnOnTor);
    await pump(tester);

    expect(find.text(l10nEn.connectionProblemTurnOnTor), findsOneWidget);
    final line = tester.getTopLeft(find.text(l10nEn.connectionProblemTurnOnTor));
    final field = tester.getTopLeft(find.widgetWithText(TextField, l10nEn.connectServerAddressLabel));
    expect(line.dy, lessThan(field.dy), reason: 'above the fields');
  });

  testWidgets('an onion address the module refused is shown at the onion field, not above the fields', (tester) async {
    status.value = const ConnectionStatus(state: LinkState.offline, problem: ConnectionProblem.invalidOnion);
    await pump(tester);

    expect(find.text(l10nEn.connectionProblemInvalidOnion), findsOneWidget, reason: 'said once');
    final error = tester.getTopLeft(find.text(l10nEn.connectionProblemInvalidOnion));
    final onion = tester.getTopLeft(find.widgetWithText(TextField, l10nEn.connectOnionAddressLabel));
    expect(error.dy, greaterThan(onion.dy), reason: 'under the onion field');
    expect(find.text(l10nEn.noConnection), findsNothing);
  });

  testWidgets('with no cause known it says there is no connection', (tester) async {
    status.value = const ConnectionStatus(state: LinkState.offline);
    await pump(tester);

    expect(find.text(l10nEn.noConnection), findsOneWidget);
  });
}
