part of 'item_list_bloc.dart';

@freezed
sealed class ItemListEvent with _$ItemListEvent {
  /// Fired once from initState.
  const factory ItemListEvent.initialize() = Initialize;

  /// Load a page. reset: true clears and reloads from page one.
  const factory ItemListEvent.loadItems({@Default(false) bool reset}) = LoadItems;
}
