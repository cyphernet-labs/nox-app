import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/model/item/item_status.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 2, 3, 4, 5);

  ItemModel buildItem({required ItemStatus status, required String name}) {
    return ItemModel(id: 'i1', name: name, description: null, status: status, createdAt: createdAt);
  }

  group('ItemModelExt.isArchived', () {
    test('is true only for ItemStatus.archived', () {
      expect(buildItem(status: ItemStatus.archived, name: 'x').isArchived, isTrue);
    });

    test('is false for ItemStatus.draft', () {
      expect(buildItem(status: ItemStatus.draft, name: 'x').isArchived, isFalse);
    });

    test('is false for ItemStatus.active', () {
      expect(buildItem(status: ItemStatus.active, name: 'x').isArchived, isFalse);
    });
  });

  group('ItemModelExt.displayName', () {
    test('falls back to Untitled for an empty name', () {
      expect(buildItem(status: ItemStatus.active, name: '').displayName, 'Untitled');
    });

    test('falls back to Untitled for a whitespace-only name', () {
      expect(buildItem(status: ItemStatus.active, name: '   ').displayName, 'Untitled');
    });

    test('returns a padded name unchanged when the trimmed value is non-empty', () {
      expect(buildItem(status: ItemStatus.active, name: '  Padded  ').displayName, '  Padded  ');
    });

    test('returns an ordinary name unchanged', () {
      expect(buildItem(status: ItemStatus.active, name: 'Hello').displayName, 'Hello');
    });
  });
}
