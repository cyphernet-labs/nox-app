import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/data/mapper/chat/chat_mapper.dart';
import 'package:nox_app/data/remote/datasource/chat_files_remote_data_source.dart';
import 'package:nox_app/data/remote/datasource/chat_remote_data_source.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:uuid/uuid.dart';

/// Cache-first chats list (5.1) over the local Sembast DB. The [ChatRemoteDataSource]
/// (mock this phase) seeds the store ONCE on first read; thereafter the list, search
/// and pagination are served from the DB, and [createChat] persists locally. No
/// backend — when transport lands, only the data-source binding swaps; the DB contract stays.
@LazySingleton(as: ChatRepository, env: [Environment.dev, Environment.prod, Environment.test])
class ChatRepositoryImpl with BaseRepositoryHelper implements ChatRepository {
  ChatRepositoryImpl(this._chatDao, this._chatRemote, this._chatFilesRemote, this._mapper, this._messageRepository);

  final ChatDao _chatDao;
  final ChatRemoteDataSource _chatRemote;
  final ChatFilesRemoteDataSource _chatFilesRemote;
  final ChatMapper _mapper;
  final MessageRepository _messageRepository;

  static const int _pageSize = GetChatsConfig.pageSize;
  static const Uuid _uuid = Uuid();

  /// One-time seed of the deterministic mock set into the local DB (empty store).
  Future<void> _seedIfEmpty() async {
    if (await _chatDao.count() > 0) return;
    final all = <ChatModel>[];
    var page = GetChatsConfig.defaultPage;
    while (true) {
      final (chats, meta) = await _chatRemote.getChats(config: GetChatsConfig.nextPage(page: page));
      all.addAll(chats);
      final next = meta.nextPage;
      if (next == null) break;
      page = next;
    }
    await _chatDao.saveData(all.map((c) => _mapper.toEntity(model: c)).toList());
  }

  @override
  Future<RepositoryResult<(List<ChatModel>, PageMetadata)>> getChats({required GetChatsConfig config}) {
    return execute<(List<ChatModel>, PageMetadata)>(() async {
      await _seedIfEmpty();
      final all = (await _chatDao.getAllSorted()).map((e) => _mapper.toModel(entity: e)).toList();
      final search = config.search?.trim().toLowerCase() ?? '';
      final filtered = search.isEmpty ? all : all.where((c) => c.name.toLowerCase().contains(search)).toList();
      final start = (config.page - 1) * _pageSize;
      final slice = filtered.skip(start).take(_pageSize).toList();
      final hasMore = start + _pageSize < filtered.length;
      return RepositoryResult<(List<ChatModel>, PageMetadata)>.success(
        data: (slice, PageMetadata(total: filtered.length, nextPage: hasMore ? config.page + 1 : null)),
      );
    });
  }

  @override
  Stream<List<ChatModel>> watchChats() async* {
    await _seedIfEmpty();
    yield* _chatDao.watch().map((entities) => entities.map((e) => _mapper.toModel(entity: e)).toList());
  }

  @override
  Future<RepositoryResult<ChatModel>> createChat({required String name}) {
    return execute<ChatModel>(() async {
      final chat = ChatModel(id: _uuid.v4(), name: name, lastMessagePreview: '', lastMessageAt: AppClock.now());
      await _chatDao.upsert(_mapper.toEntity(model: chat));
      // Seed the opening "Chat created by {label}" system line so the new thread shows
      // its genesis instead of the generic mock history (D5). Best-effort: the chat is
      // already committed, so a seeding failure MUST NOT fail the create (it would strand
      // an orphan chat). On failure the thread just falls back to the generic seed.
      try {
        await _messageRepository.seedCreatedChat(chatId: chat.id);
      } catch (error, stackTrace) {
        logRepository.error(target: this, error: error, stackTrace: stackTrace);
      }
      return RepositoryResult<ChatModel>.success(data: chat);
    });
  }

  @override
  Future<RepositoryResult<bool>> isChatNameTaken({required String name}) {
    return execute<bool>(() async {
      // Check the accumulating DB (seeded + created), not a frozen mock set (D4). No
      // seed here — the chats list has already seeded the store before create-chat is
      // reachable, and keeping this off the availability path avoids the mock seed
      // delay on every keystroke. Dart-side filter over decoded entities — a Sembast
      // Finder on the camelCase `name` key would silently match nothing under the
      // global field_rename:snake.
      //
      // CASE-INSENSITIVE, to match the case-insensitive list search (getChats): this
      // stops two case-variant chats ('Design crit' / 'design crit') both surfacing
      // under one search in the open shared space. (Chat names have no spec'd case
      // rule — unlike the case-sensitive username/label.)
      final needle = name.toLowerCase();
      final taken = (await _chatDao.getAllSorted()).any((c) => c.name.toLowerCase() == needle);
      return RepositoryResult<bool>.success(data: taken);
    });
  }

  @override
  Future<RepositoryResult<List<MessageAttachment>>> getChatFiles({required String chatId}) {
    return execute<List<MessageAttachment>>(() async {
      final files = await _chatFilesRemote.getChatFiles(chatId: chatId);
      return RepositoryResult<List<MessageAttachment>>.success(data: files);
    });
  }

  @override
  Future<void> markChatRead({required String chatId}) async {
    final chat = await _chatDao.getById(chatId);
    // No-op when absent or already read — avoids a redundant write / watch emission.
    if (chat == null || chat.unreadCount == 0) return;
    await _chatDao.upsert(chat.copyWith(unreadCount: 0));
  }

  @override
  Future<void> clean() async {
    await _chatDao.cleanData();
  }
}
