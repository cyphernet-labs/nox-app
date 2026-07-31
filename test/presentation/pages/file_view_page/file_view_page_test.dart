import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/service/file_picker_service.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/file_view_page/file_view_page.dart';
import 'package:nox_app/presentation/widgets/primitives/app_file_glyph_widget.dart';
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
  group('FileViewPage local file (P4)', () {
    testWidgets('a file with a real local path skips the mock download and enables Save at once', (tester) async {
      final src = File('${Directory.systemTemp.path}/nox_p4_src.png')..writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
      addTearDown(() => src.existsSync() ? src.deleteSync() : null);
      final file = MessageAttachment(id: 'i', type: FileType.image, name: 'shot.png', sizeBytes: 3, localPath: src.path);

      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // settle:false + a single pump — do NOT wait for the 1s mock download timer.
      await pumpApp(tester, FileViewPage(file: file), settle: false);
      await tester.pump();

      // No "download" progress bar (nothing to fetch — bytes are on disk); the size shows.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('B'), findsWidgets); // formatted size, not a % caption
    });

    testWidgets('a seeded file with no local path still runs the timed mock download (backend stand-in)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const FileViewPage(file: _file), settle: false); // pdf, no localPath
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget); // the mock "download" is running
    });
  });

  group('FileViewPage (mobile)', () {
    testWidgets('shows the file glyph, name and size after the download finishes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const FileViewPage(file: _file)); // settles the fake download timer

      expect(find.byType(AppFileGlyphWidget), findsOneWidget);
      expect(find.text('design-spec.pdf'), findsWidgets);
      expect(find.textContaining('MB'), findsWidgets);
    });

    testWidgets('Save shows the saved-to-downloads snackbar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const FileViewPage(file: _file));

      await tester.tap(find.byTooltip(l10nEn.tooltipSave));
      await tester.pump();

      expect(find.text(l10nEn.savedToDownloads), findsOneWidget);
    });
  });

  group('FileViewPage real save (F2)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await configureDependencies(Environment.test);
    });
    tearDown(() async => getIt.reset());

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
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const FileViewPage(file: _file));

      // Two glyphs on the desktop lightbox: the small leading one in the header + the hero one in the body.
      expect(find.byType(AppFileGlyphWidget), findsNWidgets(2));
      expect(find.widgetWithText(FilledButton, l10nEn.actionDownload), findsOneWidget);
    });
  });
}
