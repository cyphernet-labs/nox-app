import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';

/// Encapsulates v5 PagingState assembly (page-of-pages + keys + hasNextPage).
/// Generic over K; OFFSET default (K = item id, one item per page).
extension PagingStateExt<K, T> on PagingState<K, T> {
  ({List<T> updatedList, PagingState<K, T> pagingState, int? nextPage}) applyPage({
    required List<T> existingList,
    required (List<T>, PageMetadata) response,
    required K Function(T) keyExtractor,
  }) {
    final (incoming, meta) = response;
    final updatedList = [...existingList, ...incoming];
    final isLastPage = meta.nextPage == null;
    final pages = updatedList.map((e) => [e]).toList();
    final keys = updatedList.map(keyExtractor).toList();
    final isNoItems = updatedList.isEmpty && isLastPage;
    final newPagingState = isNoItems
        ? copyWith(pages: <List<T>>[], keys: <K>[], hasNextPage: false, isLoading: false)
        : copyWith(pages: pages, keys: keys, hasNextPage: !isLastPage, isLoading: false);
    return (updatedList: updatedList, pagingState: newPagingState, nextPage: meta.nextPage);
  }
}
