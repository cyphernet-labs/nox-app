import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/chat_card_page/chat_card_page.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/chat_thread_page.dart';
import 'package:nox_app/presentation/pages/chats_list_page/chats_list_page.dart';
import 'package:nox_app/presentation/pages/file_view_page/file_view_page.dart';
import 'package:nox_app/presentation/pages/settings_root_page/settings_root_page.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_chat_item_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_composer_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_file_chip_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_message_bubble_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_search_bar_widget.dart';
import 'package:nox_app/presentation/pages/create_chat_page/create_chat_page.dart';
import 'package:nox_app/presentation/pages/login_page/login_page.dart';
import 'package:nox_app/presentation/pages/qr_scan_page/qr_scan_page.dart';
import 'package:nox_app/presentation/pages/set_username_page/set_username_page.dart';
import 'package:nox_app/presentation/widgets/primitives/file_type.dart';
import 'package:nox_app/presentation/widgets/shell/app_bottom_bar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_create_fab_widget.dart';

import '../../utils/pump_app.dart';

/// Cross-widget accessibility checks (FR-016): tap targets >= 48x48, icon-only
/// actions expose a tooltip/semantics, and layout survives textScaler up to 2.0.
void main() {
  // M3 screens (shell / chats list) resolve ChatRepository from DI.
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  group('accessibility (FR-016)', () {
    testWidgets('composer icon-action tap targets are >= 48x48', (tester) async {
      await pumpApp(tester, AppComposerWidget(controller: TextEditingController(), sendActive: true, onSend: () {}, onAttach: () {}));

      final buttons = find.byType(IconButton);
      expect(buttons, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final size = tester.getSize(buttons.at(i));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('create FAB tap target is >= 48x48 with a tooltip', (tester) async {
      await pumpApp(tester, AppCreateFabWidget(onPressed: () {}));

      final size = tester.getSize(find.byType(FloatingActionButton));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(find.byTooltip(TextConstants.tooltipCreateChat), findsOneWidget);
    });

    testWidgets('bottom bar tab tap targets are >= 48x48', (tester) async {
      await pumpApp(tester, AppBottomBarWidget(active: AppTab.chats, onSelect: (_) {}));

      final tabs = find.byType(InkResponse);
      expect(tabs, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final size = tester.getSize(tabs.at(i));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('composer actions expose tooltips/semantics', (tester) async {
      await pumpApp(tester, AppComposerWidget(controller: TextEditingController(), sendActive: true, onSend: () {}, onAttach: () {}));

      expect(find.byTooltip(TextConstants.tooltipAttachFile), findsOneWidget);
      expect(find.byTooltip(TextConstants.tooltipSend), findsOneWidget);
    });

    testWidgets('layout survives textScaler 2.0 without overflow', (tester) async {
      await pumpApp(
        tester,
        const AppChatItemWidget(
          name: 'A long chat name that should ellipsize',
          preview: 'A long preview line that should also ellipsize',
          time: '09:00',
          unread: 12,
        ),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);

      await pumpApp(tester, AppComposerWidget(controller: TextEditingController(text: 'A long draft that should reflow')), textScale: 2.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chat + shell widgets survive textScaler 2.0 without overflow', (tester) async {
      await pumpApp(
        tester,
        const AppMessageBubbleWidget(
          isOwn: false,
          text: 'A long message that should wrap and still fit without overflowing at large text scale',
          time: '09:00',
          status: MessageStatus.sent,
        ),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);

      await pumpApp(
        tester,
        AppFileChipWidget(
          type: FileType.pdf,
          name: 'a-rather-long-attachment-name-that-could-clip.pdf',
          size: '2.4 MB',
          removable: true,
          onRemove: () {},
        ),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);

      await pumpApp(tester, const AppSearchBarWidget(value: 'a long search query that should not overflow'), textScale: 2.0);
      expect(tester.takeException(), isNull);

      await pumpApp(tester, AppBottomBarWidget(active: AppTab.chats, onSelect: (_) {}), textScale: 2.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('M2 onboarding/form screens survive textScaler 2.0 without overflow', (tester) async {
      await pumpApp(tester, const LoginPage(), textScale: 2.0, settle: false);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'LoginPage overflowed at 2.0');

      await pumpApp(tester, const SetUsernamePage(), textScale: 2.0, settle: false);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'SetUsernamePage overflowed at 2.0');

      await pumpApp(tester, const CreateChatPage(), textScale: 2.0, settle: false);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'CreateChatPage overflowed at 2.0');

      await pumpApp(tester, const QrScanPage(), textScale: 2.0, settle: false);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'QrScanPage overflowed at 2.0');
    });

    testWidgets('QR scanner icon actions expose tooltips', (tester) async {
      await pumpApp(tester, const QrScanPage(), settle: false);

      expect(find.byTooltip(TextConstants.tooltipFlashlight), findsOneWidget);
      expect(find.byTooltip(TextConstants.tooltipSwitchCamera), findsOneWidget);
    });

    testWidgets('M3 shell / settings / chats screens survive textScaler 2.0 without overflow', (tester) async {
      // settle: true drains the screens' async init timers (Initialize + the mock
      // load) and renders the loaded layout, where any overflow would surface.
      await pumpApp(tester, const TabBarShell(), textScale: 2.0);
      expect(tester.takeException(), isNull, reason: 'TabBarShell overflowed at 2.0');

      await pumpApp(tester, const SettingsRootPage(), textScale: 2.0);
      expect(tester.takeException(), isNull, reason: 'SettingsRootPage overflowed at 2.0');

      await pumpApp(tester, const ChatsListPage(), textScale: 2.0);
      expect(tester.takeException(), isNull, reason: 'ChatsListPage overflowed at 2.0');
    });

    testWidgets('M4 chat-detail screens survive textScaler 2.0 without overflow', (tester) async {
      final chat = ChatModel(id: 'chat_0', name: 'Design crit', lastMessagePreview: '', lastMessageAt: DateTime(2024, 1, 1));

      await pumpApp(tester, ChatThreadPage(chat: chat), textScale: 2.0);
      expect(tester.takeException(), isNull, reason: 'ChatThreadPage overflowed at 2.0');

      await pumpApp(tester, ChatCardPage(chat: chat), textScale: 2.0);
      expect(tester.takeException(), isNull, reason: 'ChatCardPage overflowed at 2.0');

      await pumpApp(
        tester,
        const FileViewPage(
          file: MessageAttachment(id: 'f', type: FileType.pdf, name: 'design-spec.pdf', sizeBytes: 2516582),
        ),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull, reason: 'FileViewPage overflowed at 2.0');
    });
  });
}
