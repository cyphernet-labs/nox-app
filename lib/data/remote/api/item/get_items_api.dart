import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/entity/item/items_entity.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';

/// Skeleton MOCK source for the Item harness (no real backend — FR-013). The
/// real impl wraps a Dio request builder around `ResponseEntity<ItemsEntity>`
/// (path `v1/items`, query `page`/`page_size`/`search`) — example/TBD until the
/// NOX backend is chosen.
@lazySingleton
class GetItemsApi {
  static const int _mockTotal = 47;

  Future<ResponseEntity<ItemsEntity>> execute({required GetItemsConfig config}) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    const pageSize = GetItemsConfig.pageSize;
    final start = (config.page - 1) * pageSize;
    final now = DateTime.now().toUtc().toIso8601String();
    final items = <ItemEntity>[
      for (var i = start; i < start + pageSize && i < _mockTotal; i++)
        ItemEntity(id: 'item_$i', name: 'Item #$i', status: 'active', createdAt: now, description: null),
    ];
    return ResponseEntity<ItemsEntity>(
      success: true,
      data: ItemsEntity(items: items, page: config.page, pageSize: pageSize, total: _mockTotal),
    );
  }
}
