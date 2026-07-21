import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/remote/datasource/chat_remote_data_source.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stand-in [ChatRemoteDataSource] — proves the repository routes through the
/// INTERFACE, not the concrete mock. This is the shape of the future production flip
/// (feature 016 / SC-002): a real implementation registered for the interface makes
/// the repository use it with zero repository edits.
class _SentinelChatRemoteDataSource implements ChatRemoteDataSource {
  @override
  Future<(List<ChatModel>, PageMetadata)> getChats({required GetChatsConfig config}) async {
    return (
      [ChatModel(id: 'sentinel', name: 'SENTINEL', lastMessagePreview: '', lastMessageAt: DateTime(2024))],
      const PageMetadata(total: 1),
    );
  }
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
    getIt.registerSingleton<ChatRemoteDataSource>(_SentinelChatRemoteDataSource());

    final chats = (await getIt<ChatRepository>().getChats(config: GetChatsConfig.firstPage())).data!;

    // The repository seeded from and served the rebound source — not MockChatRemoteDataSource.
    expect(chats.$1, hasLength(1));
    expect(chats.$1.first.name, 'SENTINEL');
  });
}
