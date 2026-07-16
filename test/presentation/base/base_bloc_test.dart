import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

/// Signature that mirrors BaseBloc.executeLogic's onError parameter exactly.
typedef _OnErrorSpy = FutureOr<void> Function(String? error, dynamic exception, StackTrace stackTrace);

class _ExecuteLogicEvent {
  const _ExecuteLogicEvent();
}

class _CounterState {
  const _CounterState(this.value);

  final int value;
}

/// Minimal concrete BaseBloc whose single handler runs a throwing logic()
/// through executeLogic. The optional onError spy exercises both branches.
class _TestBloc extends BaseBloc<_ExecuteLogicEvent, _CounterState> {
  _TestBloc({this.onErrorSpy}) : super(const _CounterState(0)) {
    on<_ExecuteLogicEvent>(_handle);
  }

  final _OnErrorSpy? onErrorSpy;

  Future<void> _handle(_ExecuteLogicEvent event, Emitter<_CounterState> emit) async {
    await executeLogic(() async => throw Exception('boom'), onError: onErrorSpy);
  }
}

void main() {
  group('BaseBloc.executeLogic', () {
    test('without onError, a throwing logic emits no state and does not rethrow', () async {
      final bloc = _TestBloc();
      final emissions = <_CounterState>[];
      final subscription = bloc.stream.listen(emissions.add);

      bloc.add(const _ExecuteLogicEvent());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The error is swallowed by design: no emission, state stays at the initial value.
      expect(emissions, isEmpty);
      expect(bloc.state.value, 0);

      await subscription.cancel();
      await bloc.close();
    });

    test('with onError, the callback fires exactly once with a non-empty error string and non-null exception + stackTrace', () async {
      var callCount = 0;
      String? capturedError;
      Object? capturedException;
      StackTrace? capturedStackTrace;

      final bloc = _TestBloc(
        onErrorSpy: (error, exception, stackTrace) {
          callCount++;
          capturedError = error;
          capturedException = exception;
          capturedStackTrace = stackTrace;
        },
      );

      bloc.add(const _ExecuteLogicEvent());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(callCount, 1);
      expect(capturedError, isNotNull);
      expect(capturedError, isNotEmpty);
      expect(capturedError, contains('boom'));
      expect(capturedException, isNotNull);
      expect(capturedException, isA<Exception>());
      expect(capturedStackTrace, isNotNull);

      await bloc.close();
    });
  });
}
