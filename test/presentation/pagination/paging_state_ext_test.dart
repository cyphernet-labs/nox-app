import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/presentation/pagination/paging_state_ext.dart';

void main() {
  group('PagingStateExt.applyPage', () {
    // A lightweight T = String with an identity keyExtractor (K = String).
    String keyOf(String item) => item;

    // The receiver starts mid-load so we can prove isLoading is cleared to false.
    final base = PagingState<String, String>(isLoading: true);

    test('first page append with a next page grows the list and rebuilds pages/keys one item per page', () {
      final result = base.applyPage(
        existingList: const ['a'],
        response: (const ['b', 'c'], const PageMetadata(hasMore: true, nextPage: 2)),
        keyExtractor: keyOf,
      );

      expect(result.updatedList, const ['a', 'b', 'c']);
      expect(result.nextPage, 2);

      final state = result.pagingState;
      expect(state.pages, const [
        ['a'],
        ['b'],
        ['c'],
      ]);
      expect(state.keys, const ['a', 'b', 'c']);
      expect(state.hasNextPage, isTrue);
      expect(state.isLoading, isFalse);
    });

    test('trailing page with a null next page appends and marks hasNextPage false', () {
      final result = base.applyPage(
        existingList: const ['a', 'b'],
        response: (const ['c'], const PageMetadata(hasMore: false, nextPage: null)),
        keyExtractor: keyOf,
      );

      expect(result.updatedList, const ['a', 'b', 'c']);
      expect(result.nextPage, isNull);

      final state = result.pagingState;
      expect(state.pages, const [
        ['a'],
        ['b'],
        ['c'],
      ]);
      expect(state.keys, const ['a', 'b', 'c']);
      expect(state.hasNextPage, isFalse);
      expect(state.isLoading, isFalse);
    });

    test('empty existing plus empty last page yields the no-items empty state', () {
      final result = base.applyPage(
        existingList: const <String>[],
        response: (const <String>[], const PageMetadata(hasMore: false, nextPage: null)),
        keyExtractor: keyOf,
      );

      expect(result.updatedList, isEmpty);
      expect(result.nextPage, isNull);

      final state = result.pagingState;
      expect(state.pages, isEmpty);
      expect(state.keys, isEmpty);
      expect(state.hasNextPage, isFalse);
      expect(state.isLoading, isFalse);
    });
  });
}
