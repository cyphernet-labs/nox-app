import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/api/chat/get_chat_files_api.dart';
import 'package:nox_app/data/remote/datasource/chat_files_remote_data_source.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';

/// Mock [ChatFilesRemoteDataSource] — delegates to the [GetChatFilesApi] generator.
/// Bound for all boot environments; flip to real per `contracts/di-binding.md`.
@LazySingleton(as: ChatFilesRemoteDataSource, env: [Environment.dev, Environment.prod, Environment.test])
class MockChatFilesRemoteDataSource implements ChatFilesRemoteDataSource {
  MockChatFilesRemoteDataSource(this._api);

  final GetChatFilesApi _api;

  @override
  Future<List<MessageAttachment>> getChatFiles({required String chatId}) => _api.execute(chatId: chatId);
}
