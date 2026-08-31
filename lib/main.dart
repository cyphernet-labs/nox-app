import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/sync/live_session_starter.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/app_config/app_flavor.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/log_repository.dart';
import 'package:nox_app/presentation/app/app_root.dart';

void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      final flavor = AppFlavor.getFlavor();
      final env = flavor == AppFlavorType.prod ? Environment.prod : Environment.dev;

      await Future.wait<dynamic>([
        configureDependencies(env),
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      ]);
      await getIt.allReady();
      await getIt<AppConfigRepository>().initialize(flavorType: flavor);
      // Bring the live channel up before the first screen resolves: the world
      // check and the applier subscription both have to precede the greeting,
      // and only the dev environment binds a starter at all.
      if (getIt.isRegistered<LiveSessionStarter>()) await getIt<LiveSessionStarter>().start();
      // The outgoing queue drains in EVERY flavor, unlike the socket-bound
      // starter above: a message written before the app was last closed has to
      // leave whether or not this build talks to a real server.
      getIt<OutboxService>().start();

      runApp(const AppRoot());
    },
    (error, stack) {
      if (getIt.isRegistered<LogRepository>()) {
        getIt<LogRepository>().error(target: 'main', error: error, stackTrace: stack);
      }
    },
  );
}
