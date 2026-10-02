@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/data/mapper/chat/chat_mapper.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/chat_creation.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/attachment_transfer.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/service/attachment_transfer_service.dart';
import 'package:nox_app/domain/service/connectivity_service.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/chat_thread_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/fonts.dart';
import '../../../utils/golden.dart';
import '../../../utils/pump_app.dart';

/// Screen-level golden for the 5.2 chat thread (DoD tail / E1): page-mobile (360) +
/// page-desktop (1280x800, `_wide` thread pane). The thread is a REACTIVE page
/// (watchMessages + mock seed delays), so the standard `goldenTest` harness can't be
/// used — pumpAndSettle would hang and `settle: false` would snapshot the spinner.
/// This bespoke harness mirrors `golden.dart` (frozen clock, real fonts, pinned
/// surface) but settles with BOUNDED pumps, like the reactive widget tests.
ChatModel _chat() =>
    ChatModel(id: 'chat_0', name: 'Design crit', lastMessagePreview: '', lastMessageAt: DateTime.fromMillisecondsSinceEpoch(0));

Future<void> _settleThread(WidgetTester tester) async {
  // Bounded pumps (not pumpAndSettle): the reactive watchMessages subscription + the
  // mock seed delays keep timers in flight, which pumpAndSettle would wait on forever.
  // ~2.1s drains the two-page seed (150ms each) + the debounced refresh, leaving the
  // loaded thread on a stable frame.
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// A message with a file on its way to the server: queued (its clock) with 45%
/// of its bytes up (the words and the bar under the file). Nothing drains the
/// queue in this harness, so the frame holds still.
Future<void> _seedSending() async {
  final entry = (await getIt<OutboxRepository>().enqueue(
    chatId: 'chat_0',
    text: null,
    attachment: const MessageAttachment(
      id: 'att_local',
      type: FileType.pdf,
      name: 'quarterly-report.pdf',
      sizeBytes: 2516582,
      mime: 'application/pdf',
    ),
  )).data!;
  getIt<AttachmentTransferService>()
    ..begin(entry.clientMessageId, TransferDirection.upload, chatId: entry.chatId)
    ..report(entry.clientMessageId, 0.45);
}

/// A chat this device made that is not on the server yet (phase 041): its
/// row in [creation], its "Chat created by" line and one message waiting in
/// the queue for it. Fixed id, so the frame is the same on every run.
ChatModel _createdHere(ChatCreation creation) => ChatModel(
  id: 'c_5f0e9c1d2a3b4c5d6e7f8091a2b3c4d5',
  name: 'Kitchen',
  lastMessagePreview: '',
  lastMessageAt: kGoldenClock,
  creation: creation,
);

Future<void> _seedCreatedHere(ChatModel chat) async {
  await getIt<ChatDao>().upsert(getIt<ChatMapper>().toEntity(model: chat, lastOpenedSeq: null));
  await getIt<MessageRepository>().seedCreatedChat(chatId: chat.id);
  await getIt<OutboxRepository>().enqueue(chatId: chat.id, text: 'Buy milk on the way home');
}

/// A device with no network. Not the offline debug scenario: switching to a
/// scenario empties the chat's queue, and the waiting message is the point.
class _NoNetwork implements ConnectivityService {
  @override
  Future<bool> isOnline() async => false;

  @override
  Stream<bool> watchOnline() => Stream<bool>.value(false);
}

void main() {
  setUpAll(loadNoxFonts);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase(); // fresh store → deterministic seed
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('chat_thread_page golden', () {
    for (final entry in const <(ThemeMode, String)>[(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')]) {
      final mode = entry.$1;
      final suffix = entry.$2;

      testWidgets('mobile matches the $suffix theme', (tester) async {
        AppClock.freeze(kGoldenClock);
        addTearDown(AppClock.reset);
        tester.view.devicePixelRatio = 3.0;
        tester.view.physicalSize = Constants.designSize * 3.0;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });

        await pumpApp(tester, ChatThreadPage(chat: _chat()), themeMode: mode, settle: false);
        await _settleThread(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_thread_page_$suffix.png'));
      });

      testWidgets('desktop matches the $suffix theme', (tester) async {
        AppClock.freeze(kGoldenClock);
        addTearDown(AppClock.reset);
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = kDesktopGoldenSize * 2.0;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });

        await pumpApp(tester, ChatThreadPage(chat: _chat()), themeMode: mode, settle: false);
        await _settleThread(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_thread_page_desktop_$suffix.png'));
      });

      // DoD 'Inline-error' tail: the send-error state — an own message that failed to send
      // (MessageStatus.error, tinted + retry). Seeded via the sendError scenario + an
      // auto-send (no UI interaction), settled through the same bounded-pump harness.
      testWidgets('mobile inline-error matches the $suffix theme', (tester) async {
        AppClock.freeze(kGoldenClock);
        addTearDown(AppClock.reset);
        tester.view.devicePixelRatio = 3.0;
        tester.view.physicalSize = Constants.designSize * 3.0;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });

        await pumpApp(
          tester,
          ChatThreadPage(chat: _chat(), initialScenario: ChatThreadScenario.sendError, initialSendText: 'Ping the server'),
          themeMode: mode,
          settle: false,
        );
        await _settleThread(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_thread_page_inline_error_$suffix.png'));
      });

      testWidgets('desktop inline-error matches the $suffix theme', (tester) async {
        AppClock.freeze(kGoldenClock);
        addTearDown(AppClock.reset);
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = kDesktopGoldenSize * 2.0;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });

        await pumpApp(
          tester,
          ChatThreadPage(chat: _chat(), initialScenario: ChatThreadScenario.sendError, initialSendText: 'Ping the server'),
          themeMode: mode,
          settle: false,
        );
        await _settleThread(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_thread_page_inline_error_desktop_$suffix.png'));
      });

      // A file being sent: the bubble says how far its bytes have got, on both
      // surfaces - the desktop thread pane is narrower than the phone's
      // screen is tall, and the bar has to fit the chip in both.
      testWidgets('mobile sending matches the $suffix theme', (tester) async {
        AppClock.freeze(kGoldenClock);
        addTearDown(AppClock.reset);
        tester.view.devicePixelRatio = 3.0;
        tester.view.physicalSize = Constants.designSize * 3.0;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });
        // Real async: the store's writes do not run inside the test's fake clock.
        await tester.runAsync(_seedSending);

        await pumpApp(tester, ChatThreadPage(chat: _chat()), themeMode: mode, settle: false);
        await _settleThread(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_thread_page_sending_$suffix.png'));
      });

      testWidgets('desktop sending matches the $suffix theme', (tester) async {
        AppClock.freeze(kGoldenClock);
        addTearDown(AppClock.reset);
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = kDesktopGoldenSize * 2.0;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });
        // Real async: the store's writes do not run inside the test's fake clock.
        await tester.runAsync(_seedSending);

        await pumpApp(tester, ChatThreadPage(chat: _chat()), themeMode: mode, settle: false);
        await _settleThread(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_thread_page_sending_desktop_$suffix.png'));
      });

      // The remaining debug scenarios (P10): offline (a NOTICE strip over the thread),
      // empty (no messages) and fatal (full-screen error). Each seeded via initialScenario
      // and locked on both the mobile (360) and desktop (`_wide` pane) surfaces.
      // pinRefused (036) joins them: the wrong machine answered, which is a
      // different glyph, a different sentence and an action `offline` has not
      // got - so its own baseline on both surfaces.
      for (final scenario in const [
        ChatThreadScenario.offline,
        ChatThreadScenario.pinRefused,
        ChatThreadScenario.empty,
        ChatThreadScenario.fatal,
      ]) {
        final name = scenario == ChatThreadScenario.pinRefused ? 'pin_refused' : scenario.name;

        testWidgets('mobile $name matches the $suffix theme', (tester) async {
          AppClock.freeze(kGoldenClock);
          addTearDown(AppClock.reset);
          tester.view.devicePixelRatio = 3.0;
          tester.view.physicalSize = Constants.designSize * 3.0;
          addTearDown(() {
            tester.view.resetDevicePixelRatio();
            tester.view.resetPhysicalSize();
          });

          await pumpApp(
            tester,
            ChatThreadPage(chat: _chat(), initialScenario: scenario),
            themeMode: mode,
            settle: false,
          );
          await _settleThread(tester);

          await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_thread_page_${name}_$suffix.png'));
        });

        testWidgets('desktop $name matches the $suffix theme', (tester) async {
          AppClock.freeze(kGoldenClock);
          addTearDown(AppClock.reset);
          tester.view.devicePixelRatio = 2.0;
          tester.view.physicalSize = kDesktopGoldenSize * 2.0;
          addTearDown(() {
            tester.view.resetDevicePixelRatio();
            tester.view.resetPhysicalSize();
          });

          await pumpApp(
            tester,
            ChatThreadPage(chat: _chat(), initialScenario: scenario),
            themeMode: mode,
            settle: false,
          );
          await _settleThread(tester);

          await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_thread_page_${name}_desktop_$suffix.png'));
        });
      }

      // A chat not on the server yet (phase 041): waiting with nothing to take
      // it there (no network), and refused for a taken name, with its Rename.
      // "Couldn't create" is the same strip with another sentence and action -
      // the widget test covers it. Its message waits in the queue, clocked.
      for (final (name, creation, online) in const [
        ('creation_pending', ChatCreation.pending, false),
        ('creation_name_taken', ChatCreation.nameTaken, true),
      ]) {
        for (final (surface, size, ratio) in [('', Constants.designSize, 3.0), ('_desktop', kDesktopGoldenSize, 2.0)]) {
          testWidgets('${surface.isEmpty ? 'mobile' : 'desktop'} $name matches the $suffix theme', (tester) async {
            AppClock.freeze(kGoldenClock);
            addTearDown(AppClock.reset);
            tester.view.devicePixelRatio = ratio;
            tester.view.physicalSize = size * ratio;
            addTearDown(() {
              tester.view.resetDevicePixelRatio();
              tester.view.resetPhysicalSize();
            });
            if (!online) {
              getIt.allowReassignment = true;
              getIt.registerSingleton<ConnectivityService>(_NoNetwork());
            }
            final chat = _createdHere(creation);
            // Real async: the store's writes do not run inside the test's fake clock.
            await tester.runAsync(() => _seedCreatedHere(chat));

            await pumpApp(tester, ChatThreadPage(chat: chat), themeMode: mode, settle: false);
            await _settleThread(tester);

            await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_thread_page_$name${surface}_$suffix.png'));
          });
        }
      }
    }
  });
}
