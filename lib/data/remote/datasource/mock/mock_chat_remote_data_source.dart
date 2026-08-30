import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/error_wire_entity.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chats_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/name_availability_wire_entity.dart';
import 'package:nox_app/data/remote/api/chat/get_chats_api.dart';
import 'package:nox_app/data/remote/datasource/chat_remote_data_source.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/general/onboarding_mock_data.dart';
import 'package:uuid/uuid.dart';

/// Mock [ChatRemoteDataSource] — stands in for the server on the mock-backed
/// flavors `[prod, test]`. The dev flavor resolves `RealChatRemoteDataSource`
/// instead (`specs/016-remote-datasource-seam/contracts/di-binding.md`).
///
/// It mints ids and echoes writes the way a server would, so the repository
/// runs the SAME code on both paths — the only difference is the binding.
@LazySingleton(as: ChatRemoteDataSource, env: [Environment.prod, Environment.test])
class MockChatRemoteDataSource implements ChatRemoteDataSource {
  MockChatRemoteDataSource(this._api);

  final GetChatsApi _api;
  static const Uuid _uuid = Uuid();

  /// Chats created or renamed through this mock, newest first.
  ///
  /// A read-through repository asks the SOURCE for every page, so a mock that
  /// forgot its own writes would make a freshly created chat vanish from the
  /// list — a real server would not. Holding them here keeps the mock world
  /// behaving like the thing it stands in for.
  final List<ChatWireEntity> _written = <ChatWireEntity>[];

  @override
  Future<ResponseEntity<ChatsWireEntity>> getChats({required GetChatsConfig config}) async {
    final generated = await _api.execute(config: config);
    if (_written.isEmpty || generated.data == null) return generated;
    final page = generated.data!;
    // Renames replace the generated row; creations join the front, which is
    // where the server would put them (newest activity first).
    final overrides = <String, ChatWireEntity>{for (final c in _written) c.chatId: c};
    final search = config.search?.trim().toLowerCase() ?? '';
    bool matches(ChatWireEntity c) => search.isEmpty || c.name.toLowerCase().contains(search);
    final created = _written.where((c) => !page.chats.any((g) => g.chatId == c.chatId)).where(matches).toList();
    final merged = <ChatWireEntity>[
      if (config.page == GetChatsConfig.defaultPage) ...created,
      ...page.chats.map((c) => overrides[c.chatId] ?? c).where(matches),
    ];
    return ResponseEntity<ChatsWireEntity>(
      success: true,
      data: ChatsWireEntity(chats: merged, hasMore: page.hasMore),
    );
  }

  void _remember(ChatWireEntity chat) {
    _written.removeWhere((c) => c.chatId == chat.chatId);
    _written.insert(0, chat);
  }

  @override
  Future<ResponseEntity<ChatWireEntity>> getChat({required String chatId}) async {
    // The mock world has no chat the local store does not already hold, so a
    // lookup can only be for something that does not exist.
    return const ResponseEntity<ChatWireEntity>(
      success: false,
      error: ErrorWireEntity(code: 'not_found', message: 'unknown chat'),
    );
  }

  @override
  Future<ResponseEntity<ChatWireEntity>> createChat({required String name}) async {
    final now = AppClock.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final chat = ChatWireEntity(
      chatId: 'chat_${_uuid.v4()}',
      name: name,
      createdAt: now,
      createdByLabel: '',
      lastMessagePreview: '',
      lastActivityAt: now,
    );
    _remember(chat);
    return ResponseEntity<ChatWireEntity>(success: true, data: chat);
  }

  @override
  Future<ResponseEntity<ChatWireEntity>> renameChat({required String chatId, required String name}) async {
    // A server refuses to rename something it never issued; the mock world's
    // ids are the generator's `chat_N` plus whatever this mock created.
    final known = _written.any((c) => c.chatId == chatId) || RegExp(r'^chat_\d+$').hasMatch(chatId);
    if (!known) {
      return const ResponseEntity<ChatWireEntity>(
        success: false,
        error: ErrorWireEntity(code: 'not_found', message: 'unknown chat'),
      );
    }
    final now = AppClock.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    // Only the wire-owned fields; the repository merges this onto the stored
    // row, which is exactly what it must do for a real server event too.
    final chat = ChatWireEntity(
      chatId: chatId,
      name: name,
      createdAt: now,
      createdByLabel: '',
      lastMessagePreview: '',
      lastActivityAt: now,
    );
    _remember(chat);
    return ResponseEntity<ChatWireEntity>(success: true, data: chat);
  }

  @override
  Future<ResponseEntity<NameAvailabilityWireEntity>> isNameAvailable({required String name, String? excludeChatId}) async {
    // The demo reserved set used to short-circuit inside the bloc, which put a
    // mock fixture in the presentation layer and outside the 016 seam. It lives
    // here now, so mock and live differ only by binding.
    final needle = name.trim().toLowerCase();
    final taken =
        OnboardingMockData.takenChatNames.any((t) => t.toLowerCase() == needle) ||
        _written.any((c) => c.chatId != excludeChatId && c.name.toLowerCase() == needle);
    return ResponseEntity<NameAvailabilityWireEntity>(success: true, data: NameAvailabilityWireEntity(available: !taken));
  }
}
