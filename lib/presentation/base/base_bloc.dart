import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

/// Thin base for all page BLoCs. executeLogic wraps a handler in try/catch;
/// without onError it deliberately swallows (no emit, no rethrow) — always pass
/// onError for list loads to emit an Error state.
abstract class BaseBloc<E, S> extends Bloc<E, S> {
  BaseBloc(super.initialState);

  FutureOr<void> executeLogic(
    FutureOr<void> Function() logic, {
    FutureOr<void> Function(String? error, dynamic exception, StackTrace stackTrace)? onError,
  }) async {
    try {
      await logic();
    } catch (e, s) {
      await onError?.call('$e, $s', e, s);
    }
  }
}
