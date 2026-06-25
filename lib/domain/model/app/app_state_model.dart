import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/domain/model/app/session_model.dart';

part 'app_state_model.freezed.dart';

/// Projection of the session signals onto a top-level navigation phase. NOT a
/// source of truth — recomputed cache-only on every cold start (no DAO).
/// `sessionExpired` is the one-shot reason flag, true ONLY on the `unauthorized`
/// model emitted by a forced logout.
@freezed
abstract class AppStateModel with _$AppStateModel {
  const factory AppStateModel({
    required AppStateType state,
    required SessionModel? session,
    @Default(false) bool sessionExpired,
  }) = _AppStateModel;

  /// Boot sentinel (before the first resolution).
  factory AppStateModel.init() => const AppStateModel(state: AppStateType.init, session: null);
}
