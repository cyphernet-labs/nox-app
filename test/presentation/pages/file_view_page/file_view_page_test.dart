import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/service/file_picker_service.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/file_view_page/file_view_page.dart';
import 'package:nox_app/presentation/widgets/primitives/app_file_glyph_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/pump_app.dart';

const _file = MessageAttachment(id: 'f', type: FileType.pdf, name: 'design-spec.pdf', sizeBytes: 2516582);

final l10nEn = AppLocalizationsEn();

/// A picker whose `pickSaveLocation` returns a fixed destination (or null to model a
/// cancelled save dialog) — F2 real-save tests without an OS dialog.
class _FakeSaver implements FilePickerService {
  _FakeSaver(this._dest);
  final String? _dest;
  @override
  Future<PickedFile?> pickFile() async => null;
  @override
  Future<String?> pickSaveLocation({required String suggestedName}) async => _dest;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
  });

  tearDown(() async => getIt.reset());

  group('FileViewPage local file (P4)', () {
    testWidgets('a file already on this device needs no fetch and offers Save at once', (tester) async {
      final src = File('${Directory.systemTemp.path}/nox_p4_src.png')..writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
      addTearDown(() => src.existsSync() ? src.deleteSync() : null);
      final file = MessageAttachment(id: 'i', type: FileType.image, name: 'shot.png', sizeBytes: 3, localPath: src.path);

      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, FileViewPage(file: file), settle: false);
      await tester.pump();
      await tester.pump();

      // Nothing to fetch — the bytes are on disk — so no progress bar, and the
      // size is shown rather than a percentage.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('B'), findsWidgets);
    });

    testWidgets('a file the server holds is fetched, and the bar reflects a real transfer', (tester) async {
      // No local path: the bytes have to come from the server. The mock data
      // source stands in for it, so this exercises the real code path without
      // one running.
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const FileViewPage(file: _file), settle: false);
      await tester.pump();

      // The fetch is in flight on the first frame — this is where the fake
      // 1000ms animation used to live.
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('a file whose bytes are gone ends in a terminal state, not a retry loop', (tester) async {
      // Contract §2.1: attachment_gone is "терминальное error-состояние экрана
      // файла (5.3), без кнопки повтора — не фатальный экран всего приложения".
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const FileViewPage(file: _file), settle: false);
      // The fetch is genuinely async, so wait for the OUTCOME rather than for a
      // duration: a fixed pause is the test that passes alone and fails in a
      // full run, which is exactly what it did.
      for (var i = 0; i < 100 && find.text(l10nEn.attachmentGone).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }

      // The mock holds no bytes for an id it never issued, so this is the
      // gone path. The screen says so and stays put.
      expect(find.text(l10nEn.attachmentGone), findsOneWidget);
      expect(find.text(l10nEn.actionTryAgain), findsNothing, reason: 'the contract forbids a retry here');
    });
  });

  group('FileViewPage expires_at Save gating (025)', () {
    testWidgets('an expired attachment keeps Save disabled even after the download settles', (tester) async {
      AppClock.freeze(DateTime(2026, 6, 15, 21, 30));
      addTearDown(AppClock.reset);
      final bytes = File('${Directory.systemTemp.path}/nox_expired.pdf')..writeAsBytesSync(Uint8List.fromList([1, 2]));
      addTearDown(() => bytes.existsSync() ? bytes.deleteSync() : null);
      final expired = MessageAttachment(
        id: 'f-exp',
        type: FileType.pdf,
        name: 'old-spec.pdf',
        sizeBytes: 1024,
        // On disk, so the screen is READY — the only thing that may disable
        // Save here is the retention deadline, which is what this pins.
        localPath: bytes.path,
        expiresAt: AppClock.now().subtract(const Duration(days: 1)),
      );
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, FileViewPage(file: expired)); // settles the mock download

      final saveButton = tester.widget<IconButton>(
        find.ancestor(of: find.byTooltip(l10nEn.tooltipSave), matching: find.byType(IconButton)).first,
      );
      expect(saveButton.onPressed, isNull); // gated in advance - bytes are gone server-side

      // The icon dims with the SAME predicate: a dead button must not render
      // at full onSurface intensity (mobile parity with the desktop FilledButton).
      final icon = tester.widget<AppIconWidget>(find.descendant(of: find.byWidget(saveButton), matching: find.byType(AppIconWidget)));
      expect(icon.color?.a, lessThan(1.0)); // disabled alpha, not full intensity
    });

    testWidgets('a far-future expiry (stage-1 retention) leaves Save enabled as before', (tester) async {
      AppClock.freeze(DateTime(2026, 6, 15, 21, 30));
      addTearDown(AppClock.reset);
      final bytes = File('${Directory.systemTemp.path}/nox_fresh.pdf')..writeAsBytesSync(Uint8List.fromList([1, 2]));
      addTearDown(() => bytes.existsSync() ? bytes.deleteSync() : null);
      final valid = MessageAttachment(
        id: 'f-ok',
        type: FileType.pdf,
        name: 'fresh-spec.pdf',
        sizeBytes: 1024,
        localPath: bytes.path,
        expiresAt: AppClock.now().add(const Duration(days: 3650)),
      );
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, FileViewPage(file: valid));

      // The gate under test is the retention deadline, so assert the gate:
      // whether the copy then succeeds is the F2 group's business, and it has a
      // fake picker for exactly that.
      final saveButton = tester.widget<IconButton>(
        find.ancestor(of: find.byTooltip(l10nEn.tooltipSave), matching: find.byType(IconButton)).first,
      );
      expect(saveButton.onPressed, isNotNull);
    });
  });

  group('FileViewPage (mobile)', () {
    testWidgets('shows the file glyph, name and size once the bytes are here', (tester) async {
      final bytes = File('${Directory.systemTemp.path}/nox_meta.pdf')..writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
      addTearDown(() => bytes.existsSync() ? bytes.deleteSync() : null);
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, FileViewPage(file: _file.copyWith(localPath: bytes.path)));

      expect(find.byType(AppFileGlyphWidget), findsOneWidget);
      expect(find.text('design-spec.pdf'), findsWidgets);
      expect(find.textContaining('MB'), findsWidgets);
    });

    testWidgets('Save is offered once the bytes are on this device', (tester) async {
      final bytes = File('${Directory.systemTemp.path}/nox_save_meta.pdf')..writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
      addTearDown(() => bytes.existsSync() ? bytes.deleteSync() : null);
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, FileViewPage(file: _file.copyWith(localPath: bytes.path)));

      final save = tester.widget<IconButton>(
        find.ancestor(of: find.byTooltip(l10nEn.tooltipSave), matching: find.byType(IconButton)).first,
      );
      expect(save.onPressed, isNotNull);
    });

    testWidgets('Save stays gated while the bytes are not here — it could only fail', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const FileViewPage(file: _file), settle: false);
      await tester.pump();

      final save = tester.widget<IconButton>(
        find.ancestor(of: find.byTooltip(l10nEn.tooltipSave), matching: find.byType(IconButton)).first,
      );
      expect(save.onPressed, isNull);
    });
  });

  group('FileViewPage real save (F2)', () {
    void useSaver(String? dest) {
      getIt.allowReassignment = true;
      getIt.registerSingleton<FilePickerService>(_FakeSaver(dest));
    }

    testWidgets('Save copies the real file bytes to the chosen destination', (tester) async {
      final src = File('${Directory.systemTemp.path}/nox_save_src.png')..writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));
      final dest = File('${Directory.systemTemp.path}/nox_save_dest.png');
      addTearDown(() {
        if (src.existsSync()) src.deleteSync();
        if (dest.existsSync()) dest.deleteSync();
      });
      useSaver(dest.path);
      final file = MessageAttachment(id: 'i', type: FileType.image, name: 'shot.png', sizeBytes: 4, localPath: src.path);

      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, FileViewPage(file: file)); // settles the download timer → Save enabled

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip(l10nEn.tooltipSave));
        await Future<void>.delayed(const Duration(milliseconds: 100)); // let the async copy IO complete
      });

      expect(dest.existsSync(), isTrue);
      expect(dest.readAsBytesSync(), src.readAsBytesSync()); // real bytes copied
    });

    testWidgets('an IO failure during copy degrades to the error snackbar (no crash)', (tester) async {
      final src = File('${Directory.systemTemp.path}/nox_save_src3.png')..writeAsBytesSync(Uint8List.fromList([7]));
      addTearDown(() => src.existsSync() ? src.deleteSync() : null);
      useSaver('/no/such/dir/nox_dest.png'); // parent directory missing → File.copy throws
      final file = MessageAttachment(id: 'i', type: FileType.image, name: 'x.png', sizeBytes: 1, localPath: src.path);

      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, FileViewPage(file: file));

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip(l10nEn.tooltipSave));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(find.text(l10nEn.fileDownloadError), findsOneWidget); // graceful error, no crash
    });

    testWidgets('a cancelled save writes nothing and does not crash', (tester) async {
      final src = File('${Directory.systemTemp.path}/nox_save_src2.png')..writeAsBytesSync(Uint8List.fromList([9]));
      addTearDown(() => src.existsSync() ? src.deleteSync() : null);
      useSaver(null); // user cancels the save dialog
      final file = MessageAttachment(id: 'i', type: FileType.image, name: 'x.png', sizeBytes: 1, localPath: src.path);

      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, FileViewPage(file: file));

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip(l10nEn.tooltipSave));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(tester.takeException(), isNull); // no destination written, no crash
    });
  });

  group('FileViewPage (desktop lightbox)', () {
    testWidgets('renders a centered lightbox with a Download action', (tester) async {
      final bytes = File('${Directory.systemTemp.path}/nox_wide.pdf')..writeAsBytesSync(Uint8List.fromList([1]));
      addTearDown(() => bytes.existsSync() ? bytes.deleteSync() : null);
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, FileViewPage(file: _file.copyWith(localPath: bytes.path)));

      // Two glyphs on the desktop lightbox: the small leading one in the header + the hero one in the body.
      expect(find.byType(AppFileGlyphWidget), findsNWidgets(2));
      expect(find.widgetWithText(FilledButton, l10nEn.actionDownload), findsOneWidget);
    });
  });
}
