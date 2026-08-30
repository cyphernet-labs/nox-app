import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chats_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/name_availability_wire_entity.dart';
import 'package:nox_app/data/remote/datasource/chat_remote_data_source.dart';
import 'package:nox_app/data/remote/datasource/real/socket_envelope.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';

/// The chats feature over the live socket (contract v0 §4).
@LazySingleton(as: ChatRemoteDataSource, env: [Environment.dev])
class RealChatRemoteDataSource implements ChatRemoteDataSource {
  RealChatRemoteDataSource(this._socket);

  final NoxSocketClient _socket;

  @override
  Future<ResponseEntity<ChatsWireEntity>> getChats({required GetChatsConfig config}) async {
    final search = config.search?.trim();
    final reply = await _socket.send('chats.list', <String, dynamic>{
      'page': config.page,
      'page_size': GetChatsConfig.pageSize,
      // Search belongs on the wire: the cache holds only the pages that were
      // read, so filtering locally would search the prefix, not the space.
      if (search != null && search.isNotEmpty) 'query': search,
    });
    return reply.toEnvelope(ChatsWireEntity.fromJson);
  }

  @override
  Future<ResponseEntity<ChatWireEntity>> getChat({required String chatId}) async {
    final reply = await _socket.send('chat.get', <String, dynamic>{'chat_id': chatId});
    return reply.toWrappedEnvelope('chat', ChatWireEntity.fromJson);
  }

  @override
  Future<ResponseEntity<ChatWireEntity>> createChat({required String name}) async {
    final reply = await _socket.send('chat.create', <String, dynamic>{'name': name});
    return reply.toWrappedEnvelope('chat', ChatWireEntity.fromJson);
  }

  @override
  Future<ResponseEntity<ChatWireEntity>> renameChat({required String chatId, required String name}) async {
    final reply = await _socket.send('chat.rename', <String, dynamic>{'chat_id': chatId, 'name': name});
    return reply.toWrappedEnvelope('chat', ChatWireEntity.fromJson);
  }

  @override
  Future<ResponseEntity<NameAvailabilityWireEntity>> isNameAvailable({required String name, String? excludeChatId}) async {
    final reply = await _socket.send('chat.nameAvailable', <String, dynamic>{'name': name, 'exclude_chat_id': ?excludeChatId});
    return reply.toEnvelope(NameAvailabilityWireEntity.fromJson);
  }
}
