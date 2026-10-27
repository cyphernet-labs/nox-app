import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/base/bloc_transformers.dart';

/// Throwaway harness that registers a single [String] event through
/// [debounceRestartable] and records every value its handler actually processes.
class _DebouncedBloc extends Bloc<String, List<String>> {
  _DebouncedBloc(Duration window, this.handled) : super(const <String>[]) {
    on<String>((event, emit) {
      handled.add(event);
      emit([...state, event]);
    }, transformer: debounceRestartable<String>(window));
  }

  final List<String> handled;
}

void main() {
  group('debounceRestartable', () {
    test('runs the handler exactly once for the latest value when events arrive within the window', () async {
      const window = Duration(milliseconds: 120);
      final handled = <String>[];
      final bloc = _DebouncedBloc(window, handled);

      // Two rapid events inside the debounce window: only the latest survives.
      bloc.add('NO');
      bloc.add('NOX');

      await Future<void>.delayed(window + const Duration(milliseconds: 120));

      expect(handled, ['NOX']);
      expect(bloc.state, ['NOX']);

      await bloc.close();
    });

    test('the abandoned first value never surfaces', () async {
      const window = Duration(milliseconds: 120);
      final handled = <String>[];
      final bloc = _DebouncedBloc(window, handled);

      bloc.add('NO');
      bloc.add('NOX');

      await Future<void>.delayed(window + const Duration(milliseconds: 120));

      expect(handled, isNot(contains('NO')));

      await bloc.close();
    });

    test('events spaced further apart than the window each run once', () async {
      const window = Duration(milliseconds: 80);
      final handled = <String>[];
      final bloc = _DebouncedBloc(window, handled);

      bloc.add('NO');
      await Future<void>.delayed(window + const Duration(milliseconds: 80));
      bloc.add('NOX');
      await Future<void>.delayed(window + const Duration(milliseconds: 80));

      expect(handled, ['NO', 'NOX']);
      expect(bloc.state, ['NO', 'NOX']);

      await bloc.close();
    });
  });
}
