@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/presentation/pages/chat_card_page/chat_card_page.dart';

import '../../../utils/golden.dart';

// Goldens for the Chat card (5.4) in both categories: page-mobile (the pushed
// full-screen card — AppBar + avatar/name header + the Files list) and page-desktop
// (the right side-sheet over a scrim — the _wide branch the mobile surface can't
// reach). Files come from the deterministic mock; the List/Grid toggle and the
// file-open path are exercised by the behavioral chat_card_page_test.dart.
ChatModel _sampleChat() => ChatModel(id: 'chat_0', name: 'Design crit', lastMessagePreview: '', lastMessageAt: DateTime(2024, 1, 1));

void main() {
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  // ── page — mobile (360 surface, light + dark) ──
  goldenTest('chat_card_page', () => ChatCardPage(chat: _sampleChat()));

  // ── page — desktop (1280x800 surface, light + dark): right side-sheet over scrim ──
  goldenTestDesktop('chat_card_page', () => ChatCardPage(chat: _sampleChat()));
}
