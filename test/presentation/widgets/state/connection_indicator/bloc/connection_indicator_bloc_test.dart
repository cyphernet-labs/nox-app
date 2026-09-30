import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
import 'package:nox_app/presentation/widgets/state/connection_indicator/bloc/connection_indicator_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../utils/fixed_connection_status.dart';

void main() {
  late FixedConnectionStatusService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    service = FixedConnectionStatusService(FixedConnectionStatusService.connectingTor);
    getIt.allowReassignment = true;
    getIt.registerSingleton<ConnectionStatusService>(service);
  });

  tearDown(getIt.reset);

  test('it starts from where the connection stands, before the first event', () {
    final bloc = ConnectionIndicatorBloc();
    addTearDown(bloc.close);

    expect(bloc.state.status, FixedConnectionStatusService.connectingTor);
    expect(bloc.state.isEmpty, isFalse);
  });

  blocTest<ConnectionIndicatorBloc, ConnectionIndicatorState>(
    'it follows every change of the connection status',
    build: ConnectionIndicatorBloc.new,
    act: (bloc) async {
      bloc.add(const ConnectionIndicatorEvent.started());
      await Future<void>.delayed(Duration.zero);
      service.emit(FixedConnectionStatusService.tor);
      await Future<void>.delayed(Duration.zero);
      service.emit(FixedConnectionStatusService.direct);
    },
    wait: const Duration(milliseconds: 20),
    // The service replays where it stands on listen; a bloc emits its first
    // state even when it equals the initial one.
    skip: 1,
    expect: () => [
      predicate<ConnectionIndicatorState>((s) => s.status == FixedConnectionStatusService.tor && !s.isEmpty),
      predicate<ConnectionIndicatorState>((s) => s.status == FixedConnectionStatusService.direct && s.isEmpty),
    ],
  );
}
