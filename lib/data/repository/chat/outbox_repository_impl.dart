import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/chat/outbox_entity.dart';
import 'package:nox_app/data/local/chat/outbox_copies.dart';
import 'package:nox_app/data/local/chat/outbox_dao.dart';
import 'package:nox_app/data/mapper/chat/outbox_mapper.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/outbox_entry.dart';
import 'package:nox_app/domain/model/chat/outbox_status.dart';
import 'package:nox_app/domain/model/file/unfinished_upload.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:uuid/uuid.dart';

/// Local-only repository: the queue never leaves the device until the drain
/// sends it. Bound in every environment because the thread reads it everywhere —
/// unlike the socket-bound services, which only the dev flavor has.
@LazySingleton(as: OutboxRepository, env: [Environment.dev, Environment.prod, Environment.test])
class OutboxRepositoryImpl with BaseRepositoryHelper implements OutboxRepository {
  OutboxRepositoryImpl(this._dao, this._mapper, this._copies);

  final OutboxDao _dao;
  final OutboxMapper _mapper;

  /// The files the queued sends upload from (phase 043).
  final OutboxCopies _copies;

  static const Uuid _uuid = Uuid();

  @override
  Future<RepositoryResult<OutboxEntry>> enqueue({required String chatId, String? text, MessageAttachment? attachment}) {
    return execute<OutboxEntry>(() async {
      // A BARE uuid, because contract §5 says the key is a UUID and the contract
      // is taken verbatim. The old `local_` prefix answered "is this row still
      // local?" in the string itself; the queue answers that by holding the
      // record, so the prefix bought nothing and put a non-UUID on the wire.
      final key = _uuid.v4();
      // Copied BEFORE the entry is written, so the entry never names a file
      // the queue may lose the right to read.
      final picked = attachment?.localPath;
      final copy = picked == null ? null : await _copies.keep(key: key, source: picked);
      final entry = OutboxEntry(
        clientMessageId: key,
        chatId: chatId,
        ordinal: 0, // replaced inside the enqueue transaction
        createdAt: AppClock.now(),
        status: OutboxStatus.pending,
        text: text,
        attachment: copy == null ? attachment : attachment?.copyWith(localPath: copy),
      );
      try {
        final placed = await _dao.enqueue(_mapper.toEntity(model: entry));
        return RepositoryResult<OutboxEntry>.success(data: _mapper.toModel(entity: placed));
      } catch (_) {
        if (copy != null) await _copies.drop(key);
        rethrow;
      }
    });
  }

  @override
  Stream<List<OutboxEntry>> watchQueue({String? chatId}) {
    return _dao.watch(chatId: chatId).map((entities) => [for (final entity in entities) _mapper.toModel(entity: entity)]);
  }

  @override
  Future<List<OutboxEntry>> pending() async {
    final entities = await _dao.getAllSorted();
    return [
      for (final entity in entities)
        if (entity.status == OutboxStatus.pending.name) await _current(entity),
    ];
  }

  @override
  Future<OutboxEntry?> find({required String clientMessageId}) async {
    final entity = await _dao.getById(clientMessageId);
    return entity == null ? null : _current(entity);
  }

  /// The entry, with its copy's path as it is on this run: the drain reads the
  /// file through it, and iOS moves an app's container on every update.
  Future<OutboxEntry> _current(OutboxEntity entity) async {
    final model = _mapper.toModel(entity: entity);
    final attachment = model.attachment;
    final path = attachment?.localPath;
    if (attachment == null || path == null) return model;
    return model.copyWith(
      attachment: attachment.copyWith(
        localPath: await _copies.current(key: entity.clientMessageId, path: path),
      ),
    );
  }

  @override
  Future<void> recordFailure({
    required String clientMessageId,
    required String code,
    required bool terminal,
    required bool serverAnswered,
  }) async {
    await _mutate(clientMessageId, (entity) {
      return entity.copyWith(
        attempts: entity.attempts + 1,
        refusals: serverAnswered ? entity.refusals + 1 : entity.refusals,
        lastErrorCode: code,
        status: terminal ? OutboxStatus.error.name : entity.status,
      );
    });
  }

  @override
  Future<void> attachFile({required String clientMessageId, required String? fileId}) async {
    // The bytes are confirmed: the unfinished upload is finished, and keeping
    // its handle would only invite continuing a file that needs nothing more.
    await _mutate(
      clientMessageId,
      (entity) => entity.copyWith(fileId: fileId, uploadFileId: null, uploadSourceSize: null, uploadSourceModifiedAt: null),
    );
  }

  @override
  Future<void> noteUpload({required String clientMessageId, required UnfinishedUpload? upload}) async {
    await _mutate(
      clientMessageId,
      (entity) => entity.copyWith(
        uploadFileId: upload?.fileId,
        uploadSourceSize: upload?.sourceSize,
        uploadSourceModifiedAt: upload?.sourceModifiedAt.toUtc().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<void> markPending({required String clientMessageId}) async {
    await _mutate(clientMessageId, (entity) => entity.copyWith(status: OutboxStatus.pending.name, attempts: 0, refusals: 0));
  }

  @override
  Future<bool> keepCopy({required String clientMessageId, required String at}) async {
    final entity = await _dao.getById(clientMessageId);
    final path = entity?.attachmentLocalPath;
    if (entity == null || path == null) return false;
    // Kept on an earlier pass, and the bytes are still there.
    if (path == at) return File(at).existsSync();
    if (!await _copies.moveTo(key: clientMessageId, path: path, destination: at)) return false;
    await _mutate(clientMessageId, (entity) => entity.copyWith(attachmentLocalPath: at));
    return true;
  }

  @override
  Future<void> remove({required String clientMessageId}) async {
    // The entry first: a copy that outlived its entry is only space, while an
    // entry that outlived its copy would fail its upload.
    await _dao.remove(clientMessageId);
    await _copies.drop(clientMessageId);
  }

  @override
  Future<void> removeForChat({required String chatId}) async {
    final keys = [
      for (final entity in await _dao.getAllSorted())
        if (entity.chatId == chatId) entity.clientMessageId,
    ];
    await _dao.removeForChat(chatId);
    for (final key in keys) {
      await _copies.drop(key);
    }
  }

  @override
  Future<void> moveChat({required String from, required String to}) => _dao.moveChat(from: from, to: to);

  @override
  Future<void> clean() async {
    await _dao.cleanData();
    await _copies.clear();
  }

  /// Read-modify-write of one record, delegated to the DAO so it happens in a
  /// single transaction. A vanished record is a no-op rather than an error: the
  /// drain can finish and delete an entry while a slower failure path is still
  /// on its way to marking it — and, more sharply, the user can discard one
  /// between the two halves of a read-then-write.
  Future<void> _mutate(String clientMessageId, OutboxEntity Function(OutboxEntity entity) change) async {
    await _dao.updateIfPresent(clientMessageId, change);
  }
}
