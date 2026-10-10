import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/local/app_data_root.dart';
import 'package:nox_app/data/sync/live_session_starter.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/app_config/app_flavor.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/log_repository.dart';
import 'package:nox_app/presentation/app/app_root.dart';

void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Before anything asks for a folder - the secure store's own file among
      // them: on Windows the data lives in the local application data, which a
      // roaming profile does not carry (phase 048).
      AppDataRoot.useLocalFolderOnWindows();

      final flavor = AppFlavor.getFlavor();
      final env = flavor == AppFlavorType.prod ? Environment.prod : Environment.dev;

      await Future.wait<dynamic>([
        configureDependencies(env),
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      ]);
      await getIt.allReady();
      await getIt<AppConfigRepository>().initialize(flavorType: flavor);
      // The blob half of the file chain (contract §7) is pointed at the paired
      // server by LiveSessionStarter, below, and nowhere else: a build-time
      // address belongs to no pairing, so there is no server key a connection
      // to it could be checked against.
      // One-time upgrade housekeeping, HERE and not inside a read: it is
      // settled forever on the first launch after an update, and a repository
      // read that also migrates puts that work inside the envelope which
      // decides whether a signed-in person lands on their chats or on Login.
      // The call reports rather than throws, so nothing is guarded around it.
      await sessionRepository.sweepLegacyKeys();

      // The rest of the start waits for the local data to open under its key,
      // and the first screen waits for the rest (phase 048): the splash is up
      // meanwhile - for as long as a secure store that does not answer yet
      // takes to answer - and no state is resolved from a session the start
      // has not finished with.
      final started = _start();
      appStateRepository.holdUntil(started);
      runApp(const AppRoot());
      await started;
    },
    (error, stack) {
      if (getIt.isRegistered<LogRepository>()) {
        getIt<LogRepository>().error(target: 'main', error: error, stackTrace: stack);
      }
    },
  );
}

Future<void> _start() async {
  // Out of every backup the platform makes (FR-010), and what builds before
  // phase 048 left unsealed, gone. Both best effort.
  await AppDataRoot.excludeFromBackup();
  await AppDataRoot.sweepLegacy();
  // The local data under its key, before anything reads it. A key that is
  // gone with its data still here costs the data and a pairing; a store that
  // does not answer costs a wait, never a wipe.
  await authRepository.openLocalData();
  // A session paired before phase 044 holds no server key, so nothing it
  // has could check a connection: it is wiped once, here, before anything
  // reads it, and the person pairs again (FR-025). A keychain that cannot
  // be read right now wipes nothing.
  await authRepository.retireLegacySession();
  // Bring the live channel up before the first screen resolves: the world
  // check and the applier subscription both have to precede the greeting,
  // and only the dev environment binds a starter at all.
  // Guarded because start() now empties the local world when the server
  // turns out to be a different one, and a cache that will not clear is no
  // reason to withhold the app: cached data beats no screen at all.
  if (getIt.isRegistered<LiveSessionStarter>()) {
    try {
      await getIt<LiveSessionStarter>().start();
    } on Object catch (e, s) {
      logRepository.error(target: 'main', error: e, stackTrace: s);
    }
  }
  // The outgoing queue drains in EVERY flavor, unlike the socket-bound
  // starter above: a message written before the app was last closed has to
  // leave whether or not this build talks to a real server.
  getIt<OutboxService>().start();
}
