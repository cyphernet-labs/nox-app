import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/chat_card_page/bloc/chat_card_bloc.dart';
import 'package:nox_app/presentation/pages/chat_card_page/chat_card_page.dart';
import 'package:nox_app/presentation/pages/file_view_page/file_view_page.dart';
import 'package:nox_app/presentation/widgets/chat/app_segmented_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_file_glyph_widget.dart';

import '../../../utils/pump_app.dart';

ChatModel _sampleChat() => ChatModel(id: 'chat_0', name: 'Design crit', lastMessagePreview: '', lastMessageAt: DateTime(2024, 1, 1));

final l10nEn = AppLocalizationsEn();

void main() {
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  group('ChatCardPage (mobile)', () {
    Future<void> pumpMobile(WidgetTester tester) async {
      // Pin the FlutterView to the design surface (scale 1.0) so the responsive
      // file-glyph resolves at design size and the square grid cells fit as
      // designed — setSurfaceSize alone leaves ScreenUtil at the 800x600 default.
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = Constants.designSize * 3.0;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await pumpApp(tester, ChatCardPage(chat: _sampleChat()));
      // The thread fetches its window on open (read-through), so the test has to
      // wait out the mock's latency the way it would a real server's.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the header, the Files toggle and file rows', (tester) async {
      await pumpMobile(tester);

      expect(find.text('Design crit'), findsWidgets);
      expect(find.text(l10nEn.filesSectionTitle), findsOneWidget);
      expect(find.byType(AppSegmentedWidget<FilesViewMode>), findsOneWidget);
      expect(find.byType(AppFileGlyphWidget), findsWidgets);
    });

    testWidgets('switching to Grid keeps the files visible', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.text(l10nEn.filesViewGrid));
      await tester.pumpAndSettle();

      expect(find.byType(AppFileGlyphWidget), findsWidgets);
    });

    testWidgets('tapping a file opens the file view (5.3)', (tester) async {
      await pumpMobile(tester);

      await tester.tap(find.byType(AppFileGlyphWidget).first);
      await tester.pumpAndSettle();

      expect(find.byType(FileViewPage), findsOneWidget);
    });
  });

  group('ChatCardPage (desktop side-sheet)', () {
    testWidgets('renders the Details header', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, ChatCardPage(chat: _sampleChat()));
      // The thread fetches its window on open (read-through), so the test has to
      // wait out the mock's latency the way it would a real server's.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text(l10nEn.chatInfoTitle), findsOneWidget);
      expect(find.byType(AppFileGlyphWidget), findsWidgets);
    });
  });
}
