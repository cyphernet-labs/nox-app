import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/service/app_lifecycle_service.dart';
import 'package:rxdart/rxdart.dart';

/// Visibility from Flutter's lifecycle (phase 040). `hidden`, `paused` and
/// `detached` count as background: on iOS the process is about to be frozen,
/// and Tor should be asleep before it is. `inactive` - a notification shade, a
/// call banner - does not.
@LazySingleton(as: AppLifecycleService, env: [Environment.dev, Environment.prod])
class AppLifecycleServiceImpl implements AppLifecycleService {
  AppLifecycleServiceImpl() {
    _listener = AppLifecycleListener(onStateChange: (state) => _visibility.add(_map(state)));
  }

  // Held for the life of the app, like the singleton that owns it.
  // ignore: unused_field
  late final AppLifecycleListener _listener;
  final BehaviorSubject<AppVisibility> _visibility = BehaviorSubject<AppVisibility>.seeded(AppVisibility.foreground);

  static AppVisibility _map(AppLifecycleState state) => switch (state) {
    AppLifecycleState.resumed || AppLifecycleState.inactive => AppVisibility.foreground,
    AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached => AppVisibility.background,
  };

  @override
  AppVisibility get visibility => _visibility.value;

  @override
  Stream<AppVisibility> watchVisibility() => _visibility.stream.distinct();
}

/// Always in front - the test environment has no lifecycle to observe.
@LazySingleton(as: AppLifecycleService, env: [Environment.test])
class ForegroundAppLifecycleService implements AppLifecycleService {
  @override
  AppVisibility get visibility => AppVisibility.foreground;

  @override
  Stream<AppVisibility> watchVisibility() => const Stream<AppVisibility>.empty();
}
