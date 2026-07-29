import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/service/file_picker_service.dart';
import 'package:nox_app/domain/service/qr_image_decode_service.dart';
import 'package:nox_app/general/nox_qr_envelope.dart';
import 'package:nox_app/general/qr_scanner_capability.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/login_page/login_page.dart';
import 'package:nox_app/presentation/pages/set_username_page/set_username_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/pump_app.dart';
import 'login_qr_image_test.mocks.dart';

final l10nEn = AppLocalizationsEn();

/// The Windows/Linux QR-image sign-in fallback (P14): where there's no camera scanner,
/// Login offers "pick a QR image", decodes it locally, and feeds the SAME sign-in path.
@GenerateMocks([FilePickerService, QrImageDecodeService])
void main() {
  late MockFilePickerService filePicker;
  late MockQrImageDecodeService decoder;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    filePicker = MockFilePickerService();
    decoder = MockQrImageDecodeService();
    getIt.allowReassignment = true;
    getIt.registerSingleton<FilePickerService>(filePicker);
    getIt.registerSingleton<QrImageDecodeService>(decoder);
    QrScannerCapability.debugOverride = false; // no camera → Windows/Linux branch
  });

  tearDown(() async {
    QrScannerCapability.debugOverride = null;
    await getIt.reset();
  });

  Finder imageButton() => find.widgetWithText(TextButton, l10nEn.loginScanQrImage);

  testWidgets('the QR-image button is offered where the camera scanner is absent', (tester) async {
    await pumpApp(tester, const LoginPage(demo: true));
    expect(imageButton(), findsOneWidget);
    expect(find.widgetWithText(TextButton, l10nEn.loginScanQr), findsNothing); // not the camera button
  });

  testWidgets('picking an image with a valid NOX QR signs in down the normal path', (tester) async {
    when(filePicker.pickFile()).thenAnswer((_) async => (name: 'id.png', sizeBytes: 1, extension: 'png', path: '/tmp/id.png'));
    when(decoder.decodeQr(any)).thenAnswer((_) async => NoxQrEnvelope.encode('fresh-identifier'));

    await pumpApp(tester, const LoginPage(demo: true));
    await tester.tap(imageButton());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.byType(SetUsernamePage), findsOneWidget); // decoded id → same registration route
  });

  testWidgets('an image with no valid NOX QR shows a notice and does not sign in', (tester) async {
    when(filePicker.pickFile()).thenAnswer((_) async => (name: 'x.png', sizeBytes: 1, extension: 'png', path: '/tmp/x.png'));
    when(decoder.decodeQr(any)).thenAnswer((_) async => null); // no QR in the image

    await pumpApp(tester, const LoginPage(demo: true));
    await tester.tap(imageButton());
    await tester.pump(); // resolve the pick + decode futures, schedule the notice
    await tester.pump(const Duration(milliseconds: 400)); // animate the SnackBar in

    expect(find.text(l10nEn.loginQrImageError), findsOneWidget);
    expect(find.byType(SetUsernamePage), findsNothing);
  });

  testWidgets('a second tap while the first pick is still running is ignored (review fix)', (tester) async {
    final gate = Completer<PickedFile?>();
    when(filePicker.pickFile()).thenAnswer((_) => gate.future); // first pick hangs open
    when(decoder.decodeQr(any)).thenAnswer((_) async => NoxQrEnvelope.encode('fresh-identifier'));

    await pumpApp(tester, const LoginPage(demo: true));
    await tester.tap(imageButton());
    await tester.pump(); // pick in flight → guard set, button disabled
    await tester.tap(imageButton(), warnIfMissed: false); // re-tap ignored
    await tester.pump();

    gate.complete((name: 'id.png', sizeBytes: 1, extension: 'png', path: '/tmp/id.png'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    verify(filePicker.pickFile()).called(1); // exactly one picker opened
  });

  testWidgets('cancelling the picker is a no-op (no decode, no sign-in)', (tester) async {
    when(filePicker.pickFile()).thenAnswer((_) async => null); // user cancelled

    await pumpApp(tester, const LoginPage(demo: true));
    await tester.tap(imageButton());
    await tester.pump();

    verifyNever(decoder.decodeQr(any));
    expect(find.byType(SetUsernamePage), findsNothing);
  });
}
