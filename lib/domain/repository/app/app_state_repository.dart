import 'package:nox_app/domain/model/app/app_state_model.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// Single reactive source of truth for the app lifecycle phase. In-memory
/// projection of the session signals (no DAO). See `docs/app-state-flow-migration.md`.
abstract class AppStateRepository {
  /// Replays the last resolved value to new subscribers, then forwards every
  /// subsequent resolution. Lazily triggers the first [fetchAppState] - once
  /// the start-up held by [holdUntil] is over.
  Stream<RepositoryResult<AppStateModel>> watchAppState();

  /// Holds the first resolution [watchAppState] makes until [ready] is over,
  /// however it ends (phase 048). The start-up opens the local data under its
  /// key first - and keeps the splash up, reading the key again, while the
  /// secure store does not answer - and only then may anything decide where
  /// the app goes: the session read before that is not the one the start-up
  /// leaves. [fetchAppState] itself never waits: the start-up's own logout
  /// resolves through it.
  void holdUntil(Future<void> ready);

  /// Resolves and emits the current app state (cache-only, no network). When
  /// [sessionExpired] is true, the emitted `unauthorized` model carries the
  /// one-shot session-expiry reason.
  Future<RepositoryResult<AppStateModel>> fetchAppState({bool sessionExpired = false});

  /// Last emitted phase, read SYNCHRONOUSLY (null before the first resolution).
  /// `null` means "not resolved yet" (≠ unauthorized).
  AppStateType? get currentState;

  /// Close the backing stream. Called by get_it when the singleton is disposed
  /// (e.g. test `getIt.reset()`); a no-op in production (the singleton lives forever).
  void dispose();
}
