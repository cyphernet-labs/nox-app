import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/repository/base/repository_config.dart';

part 'get_items_config.freezed.dart';

@freezed
abstract class GetItemsConfig with _$GetItemsConfig implements RepositoryConfig {
  const GetItemsConfig._();

  const factory GetItemsConfig({required int page, String? search}) = _GetItemsConfig;

  factory GetItemsConfig.firstPage({String? search}) => GetItemsConfig(page: defaultPage, search: search);

  factory GetItemsConfig.nextPage({required int page, String? search}) => GetItemsConfig(page: page, search: search);

  static const int pageSize = 20;
  static const int defaultPage = 1;
}
