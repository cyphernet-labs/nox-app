import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/presentation/pages/item_list_page/bloc/item_list_bloc.dart';

void main() {
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  blocTest<ItemListBloc, ItemListState>(
    'Initialize -> Initialized, then a page of mock items loads',
    build: ItemListBloc.new,
    act: (bloc) => bloc.add(const ItemListEvent.initialize()),
    wait: const Duration(milliseconds: 500),
    verify: (bloc) {
      final state = bloc.state;
      expect(state, isA<Initialized>());
      expect((state as Initialized).items, isNotEmpty);
      expect(state.total, greaterThan(0));
    },
  );
}
