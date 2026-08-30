part of 'item_list_bloc.dart';

@freezed
sealed class ItemListState with _$ItemListState {
  const factory ItemListState.initializing() = Initializing;

  const factory ItemListState.initialized({
    required PagingState<String, ItemModel> pagingState,
    @Default(<ItemModel>[]) List<ItemModel> items,
    @Default(GetItemsConfig.defaultPage) int nextPage,
    @Default(false) bool isLastPage,
    @Default(false) bool loadingInProgress,
  }) = Initialized;

  const factory ItemListState.error({BaseRepositoryException? exception}) = Error;
}

extension ItemListStateExt on ItemListState {
  List<ItemModel> get pagedItems => switch (this) {
    Initialized(:final items) => items,
    _ => const [],
  };

  bool get hasMore => switch (this) {
    Initialized(:final isLastPage) => !isLastPage,
    _ => false,
  };
}
