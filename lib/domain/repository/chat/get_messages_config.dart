import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/repository/base/repository_config.dart';

part 'get_messages_config.freezed.dart';

/// Per-call config for the chat thread (5.2). Mirrors `GetChatsConfig`: a 1-based
/// `page` over one chat's history. Paginates OLDER messages as the user scrolls up
/// (page 1 = the newest batch). `// TODO(backend):` real cursor/since semantics.
@freezed
abstract class GetMessagesConfig with _$GetMessagesConfig implements RepositoryConfig {
  const GetMessagesConfig._();

  const factory GetMessagesConfig({required String chatId, required int page}) = _GetMessagesConfig;

  factory GetMessagesConfig.firstPage({required String chatId}) => GetMessagesConfig(chatId: chatId, page: defaultPage);

  factory GetMessagesConfig.nextPage({required String chatId, required int page}) => GetMessagesConfig(chatId: chatId, page: page);

  static const int pageSize = 20;
  static const int defaultPage = 1;
}
