import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/remote/api/item/get_items_api.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';

void main() {
  final api = GetItemsApi();

  test('firstPage returns the full first slice of 20 items with a truthful envelope', () async {
    final response = await api.execute(config: GetItemsConfig.firstPage());

    expect(response.success, isTrue);
    final page = response.data!;
    expect(page.page, 1);
    expect(page.pageSize, GetItemsConfig.pageSize);
    expect(page.pageSize, 20);
    expect(page.total, 47);
    expect(page.items.length, 20);
    expect(page.items.first.id, 'item_0');
    expect(page.items.last.id, 'item_19');
    expect(page.items.map((item) => item.id).toList(), [for (var i = 0; i < 20; i++) 'item_$i']);
  });

  test('nextPage for page 2 returns items item_20 through item_39', () async {
    final response = await api.execute(config: GetItemsConfig.nextPage(page: 2));

    final page = response.data!;
    expect(page.page, 2);
    expect(page.items.length, 20);
    expect(page.items.first.id, 'item_20');
    expect(page.items.last.id, 'item_39');
  });

  test('nextPage for the last page 3 clamps the slice to the 7 remaining items', () async {
    final response = await api.execute(config: GetItemsConfig.nextPage(page: 3));

    final page = response.data!;
    expect(page.page, 3);
    expect(page.total, 47);
    expect(page.items.length, 7);
    expect(page.items.first.id, 'item_40');
    expect(page.items.last.id, 'item_46');
  });

  test('a page past the end returns an empty slice but keeps the page metadata', () async {
    final response = await api.execute(config: GetItemsConfig.nextPage(page: 4));

    expect(response.success, isTrue);
    final page = response.data!;
    expect(page.page, 4);
    expect(page.pageSize, 20);
    expect(page.total, 47);
    expect(page.items, isEmpty);
  });

  test('each item carries derived name, active status, null description and a parseable UTC ISO-8601 createdAt', () async {
    final response = await api.execute(config: GetItemsConfig.firstPage());

    final items = response.data!.items;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      expect(item.id, 'item_$i');
      expect(item.name, 'Item #$i');
      expect(item.status, 'active');
      expect(item.description, isNull);

      final createdAt = DateTime.parse(item.createdAt);
      expect(createdAt.isUtc, isTrue);
    }
  });
}
