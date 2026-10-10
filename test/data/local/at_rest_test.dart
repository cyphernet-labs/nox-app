import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/file/upload_ticket_wire_entity.dart';
import 'package:nox_app/data/exception/file_transfer_exception.dart';
import 'package:nox_app/data/local/app_data_root.dart';
import 'package:nox_app/data/entity/chat/message_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/local/device_vault.dart';
import 'package:nox_app/data/remote/datasource/file_remote_data_source.dart';
import 'package:nox_app/data/repository/file/file_repository_impl.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/model/file/transfer_cancellation.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_tor/vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SC-001 (phase 048): fill the local database and the files with known
/// fragments - a chat's name, a message's text, the bytes of an attachment, of
/// a download cut short, of a file waiting to be sent - and search every file
/// of the data folder for them, and for the local-data key. Not one hit.
void main() {
  // Long, and in no other file of anybody's: a hit is this test's own bytes.
  const chatName = 'NOX-AT-REST-CHAT-6b1f';
  const text = 'NOX-AT-REST-TEXT-9d2e';
  const attachment = 'NOX-AT-REST-ATTACHMENT-31c7';
  const partial = 'NOX-AT-REST-PART-a54d';
  const outgoing = 'NOX-AT-REST-OUTGOING-f08b';

  late Directory root;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppConfigRepository>().initialize(flavorType: AppFlavorType.stage);
    root = await AppDataRoot.directory();
    for (final entity in root.listSync()) {
      entity.deleteSync(recursive: true);
    }
    // The database on the disk, as the app opens it - not the tests' memory
    // one: what is searched has to be what a device writes.
    getIt.allowReassignment = true;
    getIt.registerSingleton<AppDatabase>(AppDatabaseDev(getIt<DeviceVault>()));
  });

  tearDown(() async {
    await getIt<AppDatabase>().clearEntireDatabase();
    for (final entity in root.listSync()) {
      entity.deleteSync(recursive: true);
    }
    NoxVault.clear();
    await getIt.reset();
  });

  /// [bytes] long, starting with [marker] and repeating it - so it lies in
  /// every chunk of the file, not only in the first.
  List<int> filled(String marker, int bytes) {
    final unit = utf8.encode('$marker ');
    return List<int>.generate(bytes, (i) => unit[i % unit.length]);
  }

  test('nothing of the conversation, of its files or of the key lies in the data folder (SC-001)', () async {
    // The conversation: a chat, a message waiting to be sent with a file.
    final chat = (await getIt<ChatRepository>().createChat(name: chatName)).data!;
    final picked = File('${Directory.systemTemp.path}/nox_at_rest_picked.mp4')..writeAsBytesSync(filled(outgoing, 150000));
    addTearDown(() => picked.existsSync() ? picked.deleteSync() : null);
    final queued = await getIt<OutboxRepository>().enqueue(
      chatId: chat.id,
      text: text,
      attachment: MessageAttachment(id: 'att_local', type: FileType.video, name: 'trip.mp4', sizeBytes: 150000, localPath: picked.path),
    );
    expect(queued.hasData, isTrue);

    // A message that came in.
    await getIt<MessageDao>().upsert(
      MessageEntity(
        id: 'm_1',
        chatId: chat.id,
        authorId: 'u_other',
        authorLabel: 'Bob',
        text: '$text, from the other device',
        sentAt: '2026-10-10T10:00:00.000Z',
        status: 'sent',
        isSystem: false,
        attachmentId: null,
        attachmentType: null,
        attachmentName: null,
        attachmentSizeBytes: null,
        seq: 7,
      ),
    );

    // A file that came down, and one cut short on its way.
    final files = FileRepositoryImpl(_Server(), getIt<AppConfigRepository>(), getIt<DeviceVault>());
    final whole = await files.download(fileId: 'f_whole', suggestedName: 'photo.png');
    expect(whole.hasData, isTrue);
    final cut = await files.download(fileId: 'f_cut', suggestedName: 'video.mp4');
    expect(cut.hasData, isFalse, reason: 'cut short, so a part is left');

    await getIt<AppDatabase>().close();

    final everything = root.listSync(recursive: true).whereType<File>().toList();
    final names = everything.map((f) => f.path.substring(root.path.length)).toList();
    // Not a vacuous search: the database, the attachment, the part and the
    // queue's copy are all there.
    expect(names.where((n) => n.endsWith('app_dev.db')), hasLength(1), reason: '$names');
    expect(names.where((n) => n.contains('nox_attachments') && n.endsWith('f_whole.png')), hasLength(1), reason: '$names');
    expect(names.where((n) => n.endsWith('f_cut.mp4.part')), hasLength(1), reason: '$names');
    expect(names.where((n) => n.contains('nox_outbox') && n.endsWith('nox_at_rest_picked.mp4')), hasLength(1), reason: '$names');

    final key = base64.decode((await const FlutterSecureStorage().read(key: 'device.storage_key'))!);
    final needles = <String, List<int>>{
      'chat name': utf8.encode(chatName),
      'message text': utf8.encode(text),
      'attachment': utf8.encode(attachment),
      'part': utf8.encode(partial),
      'outgoing file': utf8.encode(outgoing),
      'key': key,
      'key, base64': utf8.encode(base64.encode(key)),
      'key, hex': utf8.encode(key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()),
    };
    final hits = <String>[];
    for (final file in everything) {
      final bytes = file.readAsBytesSync();
      for (final MapEntry(key: what, value: needle) in needles.entries) {
        if (_contains(bytes, needle)) hits.add('$what in ${file.path.substring(root.path.length)}');
      }
    }
    expect(hits, isEmpty);
  });
}

/// Whether [needle] occurs in [haystack].
bool _contains(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// The server's file chain, as far as a download needs it: one file whole,
/// one that breaks after two whole chunks and a bit.
class _Server implements FileRemoteDataSource {
  @override
  Future<ResponseEntity<DownloadTicketWireEntity>> downloadBegin({required String fileId}) async =>
      ResponseEntity<DownloadTicketWireEntity>(
        success: true,
        data: DownloadTicketWireEntity(downloadUrl: '/files/$fileId', downloadToken: fileId),
      );

  @override
  Future<FetchedBytes> openBytes({required String downloadPath, required int offset, String? validator}) async {
    final cut = downloadPath.endsWith('f_cut');
    final unit = utf8.encode(cut ? 'NOX-AT-REST-PART-a54d ' : 'NOX-AT-REST-ATTACHMENT-31c7 ');
    final body = Uint8List.fromList(List<int>.generate(170000, (i) => unit[i % unit.length]));
    Stream<List<int>> bytes() async* {
      if (!cut) {
        yield body;
        return;
      }
      yield body.sublist(0, 140000);
      throw const FileTransferException(FileTransferFailure.connection);
    }

    return FetchedBytes(whole: true, total: body.length, validator: 'v1', bytes: bytes(), abandon: () {});
  }

  @override
  Future<ResponseEntity<UploadTicketWireEntity>> uploadBegin({
    required String name,
    required int sizeBytes,
    required String mime,
    String? fileId,
  }) => throw UnimplementedError();

  @override
  Future<void> putBytes({
    required String uploadPath,
    required int size,
    required int offset,
    required Stream<List<int>> body,
    TransferProgress? onProgress,
    TransferCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  void cancelTransfers() {}
}
