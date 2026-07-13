@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/chat_thread_page.dart';

import '../../../utils/golden.dart';

// Goldens for the Chat thread (5.2) in both categories: page-mobile (the pushed
// full-screen thread on the 360 surface — AppBar + message stream + composer) and
// page-desktop (the thread pane with its persistent header full-window on the wide
// surface — the _wide branch the mobile surface can't reach). The mock history is
// deterministic and resolves relative time through AppClock, which the golden
// harness freezes to kGoldenClock so the date separators stay stable day-to-day.
//
// The composer send-error inline state is locked by the behavioral bloc test
// chat_thread_bloc_send_error_test.dart, not a golden: it needs a forced send
// failure rather than a declarative seed — the same substitution the chats-list
// goldens use for interaction-only states.
ChatModel _sampleChat() => ChatModel(id: 'chat_0', name: 'Design crit', lastMessagePreview: '', lastMessageAt: DateTime(2024, 1, 1));

void main() {
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  // ── page — mobile (360 surface, light + dark) ──
  goldenTest('chat_thread_page', () => ChatThreadPage(chat: _sampleChat()));

  // ── page — desktop (1280x800 surface, light + dark): thread pane + persistent header ──
  goldenTestDesktop('chat_thread_page', () => ChatThreadPage(chat: _sampleChat()));
}
