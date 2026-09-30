import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:integration_test/integration_test.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/data/sync/live_session_starter.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:uuid/uuid.dart';

/// A device that paired earlier starts again away from home (phase 040, US1,
/// SC-001): no pairing, just the app's own start - the session it kept, its
/// own key, and Tor. Run on a simulator or an emulator right after
/// `tor_pairing_test.dart`, which leaves the session behind:
///   fvm flutter test integration_test/tor_relaunch_test.dart -d DEVICE --dart-define=nox.forceTor=true
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a paired device starts away from home and talks through Tor on its own key', (tester) async {
    await configureDependencies(Environment.dev);
    await getIt.allReady();
    await getIt<AppConfigRepository>().initialize(flavorType: AppFlavorType.stage);
    final session = await getIt<SessionRepository>().readSession();
    if (session.data == null) {
      debugPrint('SKIP: no session on this device - run tor_pairing_test.dart first');
      return;
    }
    final socket = getIt<NoxSocketClient>();
    final selector = getIt<ConnectionPathSelector>();

    final watch = Stopwatch()..start();
    await getIt<LiveSessionStarter>().start();
    await _until('live through Tor', const Duration(minutes: 4), () {
      return socket.currentPhase == SessionPhase.live && selector.currentPath == ConnectionPath.tor;
    });
    debugPrint('MEASURE: start to live through Tor ${watch.elapsedMilliseconds} ms');

    final chat = await getIt<ChatRepository>().createChat(
      name: 'Again from ${Platform.operatingSystem} ${DateTime.now().millisecondsSinceEpoch}',
    );
    expect(chat.hasData, isTrue);
    final sent = await getIt<MessageRepository>().sendMessage(
      chatId: chat.data!.id,
      clientMessageId: const Uuid().v4(),
      text: 'again through Tor',
    );
    expect(sent.hasData, isTrue);
    debugPrint('MEASURE: RSS ${(ProcessInfo.currentRss / 1048576).toStringAsFixed(1)} MB on Tor');
  }, timeout: const Timeout(Duration(minutes: 8)));
}

Future<void> _until(String what, Duration budget, FutureOr<bool> Function() done) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < budget) {
    if (await done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('not reached within ${budget.inSeconds} s: $what');
}
