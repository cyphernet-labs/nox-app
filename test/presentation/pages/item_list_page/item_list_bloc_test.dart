import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
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
      expect(state.loadingInProgress, isFalse); // page load settled
    },
  );

  // Mock source (GetItemsApi) is 47 items at pageSize 20 -> 3 pages: 20 / 20 / 7.

  blocTest<ItemListBloc, ItemListState>(
    'Initialize loads exactly the first page: 20 items, not the last page yet',
    build: ItemListBloc.new,
    act: (bloc) => bloc.add(const ItemListEvent.initialize()),
    wait: const Duration(milliseconds: 500),
    verify: (bloc) {
      final state = bloc.state as Initialized;
      expect(state.items, hasLength(20));
      expect(state.isLastPage, isFalse);
      expect(state.hasMore, isTrue); // hasMore == !isLastPage (state extension)
      expect(state.loadingInProgress, isFalse);
    },
  );

  blocTest<ItemListBloc, ItemListState>(
    'a reset:false loadItems appends page two: 20 -> 40 items, still not the last page',
    build: ItemListBloc.new,
    act: (bloc) async {
      bloc.add(const ItemListEvent.initialize()); // page 1 (auto reset:true load)
      await Future<void>.delayed(const Duration(milliseconds: 400));
      bloc.add(const ItemListEvent.loadItems()); // page 2, reset defaults to false
    },
    wait: const Duration(milliseconds: 500),
    verify: (bloc) {
      final state = bloc.state as Initialized;
      expect(state.items, hasLength(40));
      expect(state.isLastPage, isFalse);
      expect(state.hasMore, isTrue);
      expect(state.loadingInProgress, isFalse);
    },
  );

  blocTest<ItemListBloc, ItemListState>(
    'appending page two then page three reaches 47 items, the last page (hasMore false)',
    build: ItemListBloc.new,
    act: (bloc) async {
      bloc.add(const ItemListEvent.initialize()); // page 1
      await Future<void>.delayed(const Duration(milliseconds: 400));
      bloc.add(const ItemListEvent.loadItems()); // page 2 -> 40
      await Future<void>.delayed(const Duration(milliseconds: 400));
      bloc.add(const ItemListEvent.loadItems()); // page 3 -> 47 (7 items)
    },
    wait: const Duration(milliseconds: 500),
    verify: (bloc) {
      final state = bloc.state as Initialized;
      expect(state.items, hasLength(47));
      expect(state.isLastPage, isTrue);
      expect(state.hasMore, isFalse);
      expect(state.loadingInProgress, isFalse);
    },
  );

  blocTest<ItemListBloc, ItemListState>(
    'a loadItems dispatched while a load is in progress is a no-op (loadingInProgress guard)',
    build: ItemListBloc.new,
    seed: () => ItemListState.initialized(pagingState: PagingState<String, ItemModel>(), loadingInProgress: true),
    act: (bloc) => bloc.add(const ItemListEvent.loadItems()),
    expect: () => const <ItemListState>[], // guard returns before any emit
    verify: (bloc) {
      final state = bloc.state as Initialized;
      expect(state.loadingInProgress, isTrue); // seed untouched
      expect(state.items, isEmpty);
    },
  );
}
