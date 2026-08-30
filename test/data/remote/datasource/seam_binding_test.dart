import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chats_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/name_availability_wire_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/remote/datasource/chat_remote_data_source.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stand-in [ChatRemoteDataSource] — proves the repository routes through the
/// INTERFACE, not the concrete mock. This is the shape of the future production flip
/// (feature 016 / SC-002): a real implementation registered for the interface makes
/// the repository use it with zero repository edits. Returns the reference
/// `ResponseEntity<ChatsWireEntity>` envelope (feature 018/S4).
class _SentinelChatRemoteDataSource implements ChatRemoteDataSource {
  @override
  Future<ResponseEntity<ChatsWireEntity>> getChats({required GetChatsConfig config}) async {
    return ResponseEntity<ChatsWireEntity>(
      success: true,
      data: const ChatsWireEntity(
        chats: [
          ChatWireEntity(
            chatId: 'sentinel',
            name: 'SENTINEL',
            createdAt: 1704067200,
            createdByLabel: 'Sentinel',
            lastMessagePreview: '',
            lastActivityAt: 1704067200,
          ),
        ],
        hasMore: false,
      ),
    );
  }

  @override
  Future<ResponseEntity<ChatWireEntity>> getChat({required String chatId}) async => const ResponseEntity<ChatWireEntity>(success: false);

  @override
  Future<ResponseEntity<ChatWireEntity>> createChat({required String name}) async => const ResponseEntity<ChatWireEntity>(success: false);

  @override
  Future<ResponseEntity<ChatWireEntity>> renameChat({required String chatId, required String name}) async =>
      const ResponseEntity<ChatWireEntity>(success: false);

  @override
  Future<ResponseEntity<NameAvailabilityWireEntity>> isNameAvailable({required String name, String? excludeChatId}) async =>
      const ResponseEntity<NameAvailabilityWireEntity>(success: false);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase(); // empty store → the repo seeds from the data source
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('rebinding ChatRemoteDataSource routes ChatRepository through it — zero repo edits (SC-002)', () async {
    // Rebind the interface BEFORE the lazy ChatRepository is first resolved, so it is
    // constructed with the sentinel source (exactly what an env-scoped real binding does).
    getIt.allowReassignment = true;
    addTearDown(() => getIt.allowReassignment = false); // don't leave the global flag flipped
    getIt.registerSingleton<ChatRemoteDataSource>(_SentinelChatRemoteDataSource());

    final chats = (await getIt<ChatRepository>().getChats(config: GetChatsConfig.firstPage())).data!;

    // The repository seeded from and served the rebound source — not MockChatRemoteDataSource.
    expect(chats.$1, hasLength(1));
    expect(chats.$1.first.name, 'SENTINEL');
  });
}
