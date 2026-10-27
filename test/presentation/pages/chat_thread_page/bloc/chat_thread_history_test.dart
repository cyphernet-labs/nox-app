import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/message_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/messages_wire_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/remote/datasource/message_remote_data_source.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A server holding 60 messages of one chat at consecutive seqs 101..160 -
/// the normal case on a one-person server, where nothing else writes to the
/// journal between them.
class _Server implements MessageRemoteDataSource {
  final List<int?> askedBefore = <int?>[];
  final List<MessageWireEntity> all = [
    for (var seq = 101; seq <= 160; seq++)
      MessageWireEntity(
        messageId: 'm$seq',
        seq: seq,
        chatId: 'chat_history',
        authorId: 'u_other',
        authorLabel: 'Aria',
        sentAt: 1759600000 + seq,
        body: BodyWireEntity(type: 'text', text: 'message $seq'),
      ),
  ];

  @override
  Future<ResponseEntity<MessagesWireEntity>> getMessages({required GetMessagesConfig config}) async {
    askedBefore.add(config.beforeSeq);
    var end = all.length;
    final before = config.beforeSeq;
    if (before != null) {
      while (end > 0 && all[end - 1].seq >= before) {
        end--;
      }
    }
    final start = (end - config.wireLimit) < 0 ? 0 : end - config.wireLimit;
    return ResponseEntity<MessagesWireEntity>(
      success: true,
      data: MessagesWireEntity(messages: all.sublist(start, end), hasMore: start > 0),
    );
  }

  @override
  Future<ResponseEntity<MessageWireEntity>> sendMessage({
    required String chatId,
    required String clientMessageId,
    String? text,
    MessageAttachment? attachment,
  }) => throw UnimplementedError();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
  });

  tearDown(() async => getIt.reset());

  test('scrolling a thread back to its start loads every message, with no hole at a window edge', () async {
    // The "chat created" line sits one seq below the oldest loaded message, at a
    // seq a real message holds here. Taken as the scroll-up cursor, it made the
    // next window start one below it, and that message was never fetched.
    final server = _Server();
    getIt.allowReassignment = true;
    getIt.registerSingleton<MessageRemoteDataSource>(server);
    final bloc = ChatThreadBloc()..add(const ChatThreadEvent.initialize('chat_history'));
    addTearDown(bloc.close);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    for (var i = 0; i < 6 && (bloc.state as Initialized).pagingState.hasNextPage; i++) {
      bloc.add(const ChatThreadEvent.loadMessages()); // a scroll-up
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    final loaded = {for (final m in (bloc.state as Initialized).items.where((m) => !m.isSystem)) m.seq};
    final missing = [
      for (var seq = 101; seq <= 160; seq++)
        if (!loaded.contains(seq)) seq,
    ];
    expect(missing, isEmpty, reason: 'asked before_seq: ${server.askedBefore}');
    // Each row once, and the "chat created" line where it belongs - at the top,
    // not left mid-thread at the seq it had before the older batches came in.
    final thread = (bloc.state as Initialized).allMessages;
    expect(thread.map((m) => m.id).toSet().length, thread.length);
    expect(thread.first.isSystem, isTrue);
    expect(thread.where((m) => m.isSystem), hasLength(1));
  });
}
