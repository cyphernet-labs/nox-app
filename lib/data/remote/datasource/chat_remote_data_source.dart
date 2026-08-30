import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chats_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/name_availability_wire_entity.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';

/// Network boundary for the chats feature (5.1), aggregating everything the
/// server owns about chats behind one interface (feature 016).
///
/// Creation, renaming and the name check live here rather than in the
/// repository because **the server is the authority on name uniqueness**
/// (contract §4): a chat minted locally would carry an id the server never
/// issued and would never reach anyone else.
abstract class ChatRemoteDataSource {
  Future<ResponseEntity<ChatsWireEntity>> getChats({required GetChatsConfig config});

  /// One chat by id. Needed for an event about a chat outside the loaded
  /// prefix: `message.new` carries a Message, never the Chat it belongs to.
  Future<ResponseEntity<ChatWireEntity>> getChat({required String chatId});

  /// Creates a chat; the reply carries the server-issued id and timestamps.
  /// A taken name comes back as the typed `name_taken` failure.
  Future<ResponseEntity<ChatWireEntity>> createChat({required String name});

  /// Renames a chat (open space: anyone may). Uniqueness excludes the chat
  /// itself, per contract §4.
  Future<ResponseEntity<ChatWireEntity>> renameChat({required String chatId, required String name});

  /// Whether a name is free, checked by the server (case-insensitive).
  /// [excludeChatId] omits one chat — a rename never collides with itself.
  Future<ResponseEntity<NameAvailabilityWireEntity>> isNameAvailable({required String name, String? excludeChatId});
}
