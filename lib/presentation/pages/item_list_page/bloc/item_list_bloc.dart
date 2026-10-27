import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';
import 'package:nox_app/presentation/pagination/paging_state_ext.dart';

part 'item_list_bloc.freezed.dart';
part 'item_list_event.dart';
part 'item_list_state.dart';

/// Verification-harness BLoC (lean: initialize + paginated load). PagingState
/// lives in the state (v5 stateless). Loads are sequential() to avoid page races.
class ItemListBloc extends BaseBloc<ItemListEvent, ItemListState> {
  ItemListBloc() : super(const ItemListState.initializing()) {
    on<Initialize>(_onInitialize);
    on<LoadItems>(_onLoadItems, transformer: sequential());
  }

  final ItemRepository _itemRepository = getIt<ItemRepository>();

  FutureOr<void> _onInitialize(Initialize event, Emitter<ItemListState> emit) async {
    emit(ItemListState.initialized(pagingState: PagingState<String, ItemModel>()));
    add(const ItemListEvent.loadItems(reset: true));
  }

  FutureOr<void> _onLoadItems(LoadItems event, Emitter<ItemListState> emit) async {
    final current = state;
    if (current is! Initialized) return;
    if (current.loadingInProgress) return;

    final isReset = event.reset;
    if (!isReset && !current.pagingState.hasNextPage) return;

    final nextPageKey = isReset ? GetItemsConfig.defaultPage : current.nextPage;
    final existingList = isReset ? <ItemModel>[] : current.items;
    final basePagingState = isReset
        ? PagingState<String, ItemModel>(isLoading: true)
        : current.pagingState.copyWith(isLoading: true, error: null);

    emit(current.copyWith(loadingInProgress: true, items: existingList, pagingState: basePagingState));

    await executeLogic(
      () async {
        final config = GetItemsConfig.nextPage(page: nextPageKey);
        final result = await _itemRepository.getItems(config: config);

        final live = state;
        if (live is! Initialized) return;

        result.match<void>(
          onData: (data) {
            final (items, PageMetadata metadata) = data;
            final r = basePagingState.applyPage(existingList: existingList, response: (items, metadata), keyExtractor: (e) => e.id);
            emit(
              live.copyWith(
                items: r.updatedList,
                pagingState: r.pagingState,
                nextPage: r.nextPage ?? live.nextPage,
                isLastPage: !metadata.hasMore,
                loadingInProgress: false,
              ),
            );
          },
          onError: (exception) {
            emit(live.copyWith(pagingState: live.pagingState.copyWith(isLoading: false, error: exception), loadingInProgress: false));
          },
        );
      },
      onError: (error, exception, stackTrace) {
        final live = state;
        if (live is Initialized) {
          emit(live.copyWith(loadingInProgress: false, pagingState: live.pagingState.copyWith(isLoading: false)));
        }
      },
    );
  }
}
