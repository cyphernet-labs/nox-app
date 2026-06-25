import 'package:nox_app/domain/model/app/app_state_model.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// Single reactive source of truth for the app lifecycle phase. In-memory
/// projection of the session signals (no DAO). See `docs/app-state-flow-migration.md`.
abstract class AppStateRepository {
  /// Replays the last resolved value to new subscribers, then forwards every
  /// subsequent resolution. Lazily triggers the first [fetchAppState].
  Stream<RepositoryResult<AppStateModel>> watchAppState();

  /// Resolves and emits the current app state (cache-only, no network). When
  /// [sessionExpired] is true, the emitted `unauthorized` model carries the
  /// one-shot session-expiry reason.
  Future<RepositoryResult<AppStateModel>> fetchAppState({bool sessionExpired = false});

  /// Last emitted phase, read SYNCHRONOUSLY (null before the first resolution).
  /// `null` means "not resolved yet" (≠ unauthorized).
  AppStateType? get currentState;
}
