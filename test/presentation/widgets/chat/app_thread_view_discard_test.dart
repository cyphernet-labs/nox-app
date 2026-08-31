import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart';
import 'package:nox_app/presentation/widgets/chat/app_message_bubble_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_thread_view_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/pump_app.dart';

/// The discard gesture has to exist at BOTH widths (Principle VI): the thread
/// is one widget, but a mouse cannot long-press comfortably and a phone has no
/// secondary click, so each width needs its own way in.
void main() {
  ChatModel chat() =>
      ChatModel(id: 'chat_0', name: 'Design crit', lastMessagePreview: '', lastMessageAt: DateTime.fromMillisecondsSinceEpoch(0));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
  });

  tearDown(() async => getIt.reset());

  Future<Finder> queuedBubble(WidgetTester tester, Size surface) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Offline: the send is queued and stays pending — the state the gesture is
    // for, and the one that now outlives the process.
    await pumpApp(
      tester,
      AppThreadViewWidget(chat: chat(), initialScenario: ChatThreadScenario.offline, initialSendText: 'stuck forever'),
      settle: false,
    );
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    return find.ancestor(of: find.text('stuck forever'), matching: find.byType(AppMessageBubbleWidget));
  }

  testWidgets('a long press discards a stuck message on the narrow surface', (tester) async {
    final bubble = await queuedBubble(tester, const Size(420, 900));
    expect(bubble, findsOneWidget);

    await tester.longPress(find.text('stuck forever'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(find.text('stuck forever'), findsNothing);
    expect(await getIt<OutboxRepository>().pending(), isEmpty); // gone from the store, not just the screen
  });

  testWidgets('a secondary click discards it on the wide surface', (tester) async {
    final bubble = await queuedBubble(tester, const Size(1200, 900));
    expect(bubble, findsOneWidget);

    // A mouse cannot long-press comfortably, so the desktop half of the same
    // affordance is the right button.
    // Aim at the TEXT, not the bubble row: an own bubble is right-aligned inside
    // a full-width row, so at desktop width the row's centre is empty space.
    await tester.tap(find.text('stuck forever'), buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(find.text('stuck forever'), findsNothing);
    expect(await getIt<OutboxRepository>().pending(), isEmpty);
  });
}
