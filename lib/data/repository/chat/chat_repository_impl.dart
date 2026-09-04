import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/general/identity_mock_data.dart';
import 'package:nox_app/data/entity/chat/chat_entity.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/data/mapper/chat/chat_mapper.dart';
import 'package:nox_app/data/mapper/chat/chat_wire_mapper.dart';
import 'package:nox_app/data/remote/datasource/chat_remote_data_source.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';

/// Chats list (5.1): read-through cache over the local Sembast DB.
///
/// Each page is fetched from the [ChatRemoteDataSource] and persisted, so the
/// store is a CACHE of what has been seen rather than a claim to hold
/// everything. That matters against a live server: the previous design walked
/// every page on first read, which is fine for a 28-chat mock world and an
/// unbounded preload against a shared space of unknown size (FR-016).
///
/// Writes go to the server too — it owns chat ids and name uniqueness (§4) — and
/// what comes back is MERGED onto the stored row, never written over it: the
/// wire does not carry the device-local unread count (§6, §8.3).
@LazySingleton(as: ChatRepository, env: [Environment.dev, Environment.prod, Environment.test])
class ChatRepositoryImpl with BaseRepositoryHelper implements ChatRepository {
  ChatRepositoryImpl(
    this._chatDao,
    this._chatRemote,
    this._mapper,
    this._wireMapper,
    this._messageRepository,
    this._messageDao,
    this._session,
  );

  final ChatDao _chatDao;
  final ChatRemoteDataSource _chatRemote;
  final ChatMapper _mapper;
  final ChatWireMapper _wireMapper;
  final MessageRepository _messageRepository;
  final MessageDao _messageDao;
  final SessionRepository _session;

  static const int _pageSize = GetChatsConfig.pageSize;

  /// Writes wire rows into the cache WITHOUT clobbering device-local state.
  ///
  /// Unread lives only on this device (§8.3) — a wire row carries no such
  /// field, so overwriting the stored row would silently clear the badge. A row
  /// seen for the first time takes the mock world's unread overlay; a row that
  /// already exists keeps whatever count it had.
  /// Returns the rows as they now stand in the cache — NOT the wire rows: the
  /// caller must render the merged result, or the device-local unread count
  /// would be missing from the very page that just refreshed it.
  Future<List<ChatModel>> _persistWire(List<ChatModel> wire) async {
    if (wire.isEmpty) return const <ChatModel>[];
    final merged = <ChatEntity>[];
    for (final chat in wire) {
      final existing = await _chatDao.getById(chat.id);
      // The stored number is carried forward untouched and read by nobody: the
      // badge is recounted from the read mark. Seeding a value here used to
      // hand badges to chats the person had never opened, which contradicts
      // the product rule that an unopened chat shows none.
      final unread = existing?.unreadCount ?? 0;
      merged.add(
        _mapper.toEntity(
          model: chat.copyWith(unreadCount: unread),
          lastOpenedSeq: existing?.lastOpenedSeq,
        ),
      );
    }
    await _chatDao.saveData(merged);
    // Through the same recount as the cache path: the connected read must not
    // hand the UI a different number than the cached one for the same rows.
    return _withRecountedBadges(merged);
  }

  /// Every id a message written on THIS device could carry.
  ///
  /// Not the single resolved id: `resolveIdentity` falls back to the login
  /// identifier while the server-minted author id is not known yet, and in
  /// that window a single-value comparison stops matching - so own messages
  /// would start counting as unread. The set is collision-free by contract:
  /// server ids are `u_` + 16 hex and can never equal a login identifier.
  Future<Set<String>> _ownIds() async {
    final session = (await _session.readSession()).data;
    return <String>{?session?.authorId, ?session?.identifier, IdentityMockData.fallbackOwnId}..removeWhere((id) => id.isEmpty);
  }

  /// Turns stored rows into models whose badge is RECOUNTED from each chat's
  /// read mark, rather than read from the stored number.
  ///
  /// Every path that hands chats to the UI goes through here. The stored
  /// `unreadCount` column is now vestigial - a leftover of the counter this
  /// replaced - and reading it would resurrect the very behaviour the contract
  /// forbids: a running total that double-counts the duplicates §3 permits and
  /// that the sender's own echo increments.
  Future<List<ChatModel>> _withRecountedBadges(List<ChatEntity> entities) async {
    // Resolved ONCE per call, not per chat: this reads secure storage, and the
    // chats list re-reads its pages on every watch tick.
    final ownIds = await _ownIds();
    final models = <ChatModel>[];
    for (final entity in entities) {
      final unread = await _messageDao.countUnread(chatId: entity.id, aboveSeq: entity.lastOpenedSeq, excludeAuthors: ownIds);
      models.add(_mapper.toModel(entity: entity).copyWith(unreadCount: unread));
    }
    return models;
  }

  /// Serves one page out of the cache — the answer when the channel is down.
  Future<(List<ChatModel>, PageMetadata)> _cachedPage(GetChatsConfig config) async {
    final entities = await _chatDao.getAllSorted();
    final all = await _withRecountedBadges(entities);
    final search = config.search?.trim().toLowerCase() ?? '';
    final filtered = search.isEmpty ? all : all.where((c) => c.name.toLowerCase().contains(search)).toList();
    final start = (config.page - 1) * _pageSize;
    final slice = filtered.skip(start).take(_pageSize).toList();
    // The cache cannot know what the server still holds, so a FULL page means
    // "possibly more" and a short one means "this is all there is". Deriving it
    // from the cache size instead would tell the list there are no more pages
    // the moment it refreshed, permanently disabling load-more.
    final hasMore = slice.length == _pageSize;
    return (slice, PageMetadata(hasMore: hasMore, nextPage: hasMore ? config.page + 1 : null));
  }

  @override
  Future<RepositoryResult<(List<ChatModel>, PageMetadata)>> getChats({required GetChatsConfig config}) {
    return execute<(List<ChatModel>, PageMetadata)>(() async {
      // A cache-only read never reaches the wire (the live refresh tick).
      if (config.cachedOnly) {
        return RepositoryResult<(List<ChatModel>, PageMetadata)>.success(data: await _cachedPage(config));
      }
      try {
        // Search goes to the server: once pages are fetched on demand the cache
        // holds only what has been scrolled, and filtering it locally would
        // quietly turn "search the shared space" into "search what I loaded".
        final response = await _chatRemote.getChats(config: config);
        final data = unwrapEnvelope(response, 'chats');
        final page = await _persistWire(_wireMapper.toListModel(entities: data.chats));
        return RepositoryResult<(List<ChatModel>, PageMetadata)>.success(
          data: (page, PageMetadata(hasMore: data.hasMore, nextPage: data.hasMore ? config.page + 1 : null)),
        );
      } on SocketUnavailableException {
        // A dead channel falls back to the cache; a typed refusal from the
        // server is an answer, not an outage, and must reach the caller.
        logRepository.debug(target: this, message: 'chats: serving page ${config.page} from cache (channel down)');
        return RepositoryResult<(List<ChatModel>, PageMetadata)>.success(data: await _cachedPage(config));
      }
    });
  }

  @override
  Stream<List<ChatModel>> watchChats() async* {
    // A pure projection of the cache: fetching belongs to the paged read, which
    // is the only path that knows WHICH page is wanted. A cold store simply
    // emits empty until the first page lands.
    yield* _chatDao.watch().map((entities) => entities.map((e) => _mapper.toModel(entity: e)).toList());
  }

  @override
  Stream<ChatModel?> watchChat({required String chatId}) async* {
    // No seed here (unlike watchChats): the card/thread pass the chat in as fallback and
    // the row already exists once the list has loaded — watching one row must not drag in
    // the mock chats-seed delay on every card/thread open.
    yield* _chatDao.watchById(chatId).map((entity) => entity == null ? null : _mapper.toModel(entity: entity));
  }

  @override
  Future<RepositoryResult<ChatModel>> updateChatName({required String chatId, required String name}) {
    return execute<ChatModel>(() async {
      // The server decides whether the rename is allowed (uniqueness, §4) and a
      // taken name comes back as the typed `name_taken` failure the create/rename
      // screens render at the field.
      final response = await _chatRemote.renameChat(chatId: chatId, name: name);
      final wire = _wireMapper.toModel(entity: unwrapEnvelope(response, 'chat'));
      // Merge, never replace: the reply carries no unread count.
      final existing = await _chatDao.getById(chatId);
      final merged = _mapper.toEntity(
        model: wire.copyWith(unreadCount: existing?.unreadCount ?? 0),
        lastOpenedSeq: existing?.lastOpenedSeq,
      );
      await _chatDao.upsert(merged);
      return RepositoryResult<ChatModel>.success(data: _mapper.toModel(entity: merged));
    });
  }

  @override
  Future<RepositoryResult<ChatModel>> createChat({required String name}) {
    return execute<ChatModel>(() async {
      // The id comes from the server, not from here: a locally minted uuid would
      // name a chat nobody else can address, and the server's own row would then
      // arrive as a second, duplicate entry.
      final response = await _chatRemote.createChat(name: name);
      final chat = _wireMapper.toModel(entity: unwrapEnvelope(response, 'chat'));
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
  Future<RepositoryResult<bool>> isChatNameTaken({required String name, String? excludeChatId}) {
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
      // excludeChatId (rename): a chat never collides with its OWN current name — only a
      // DIFFERENT chat holding the name counts as taken.
      final stored = await _chatDao.getAllSorted();
      // Renaming a chat to its OWN name (any case variant) is always allowed —
      // answered here rather than on the wire, because the server would only see
      // a name that is indeed taken and could not know it is taken by the very
      // chat being renamed.
      if (excludeChatId != null && stored.any((c) => c.id == excludeChatId && c.name.toLowerCase() == needle)) {
        return const RepositoryResult<bool>.success(data: false);
      }
      final localHit = stored.any((c) => c.id != excludeChatId && c.name.toLowerCase() == needle);
      // A local hit is already an answer and costs no round trip. Otherwise ask
      // the server, which is the authority and sees names this device has never
      // paged in; a dead channel falls back to the local answer rather than
      // blocking the keystroke.
      if (localHit) return const RepositoryResult<bool>.success(data: true);
      try {
        final response = await _chatRemote.isNameAvailable(name: name, excludeChatId: excludeChatId);
        return RepositoryResult<bool>.success(data: !unwrapEnvelope(response, 'availability').available);
      } on RepositoryException catch (e) {
        if (e != RepositoryException.connection) rethrow;
        return const RepositoryResult<bool>.success(data: false);
      }
    });
  }

  @override
  Future<RepositoryResult<List<MessageAttachment>>> getChatFiles({required String chatId, bool refresh = false}) {
    return execute<List<MessageAttachment>>(() async {
      // Chat files are a local derivation from the persisted messages, not a remote
      // fetch — the 016 ChatFilesRemoteDataSource is retired (feature 017 / E3).
      final files = await _messageRepository.chatFiles(chatId: chatId, refresh: refresh);
      return RepositoryResult<List<MessageAttachment>>.success(data: files);
    });
  }

  @override
  /// Records that the chat was seen up to whatever is cached for it.
  ///
  /// Advances to the highest cached seq rather than to "now": that is exactly
  /// what was on screen. It fires on any load that RETURNED, online or not -
  /// an offline open serves the cache and is a real open. Opening offline with
  /// nothing cached therefore marks 0, and history that arrives later counts
  /// as unread, which is true: the person never saw it.
  @override
  Future<void> markChatRead({required String chatId}) async {
    final head = await _messageDao.highestSeq(chatId) ?? 0;
    await _chatDao.advanceReadMark(chatId: chatId, seq: head, ceiling: head);
  }

  @override
  Future<void> clearReadMarks() => _chatDao.clearReadMarks();

  @override
  Future<void> clean() async {
    await _chatDao.cleanData();
  }
}
