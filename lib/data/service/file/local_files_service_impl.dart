import 'dart:io';
import 'dart:typed_data';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/local/picker_copies.dart';
import 'package:nox_app/data/local/device_vault.dart';
import 'package:nox_app/data/local/sealed_file.dart';
import 'package:nox_app/data/service/file/temp_copies.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/service/local_files_service.dart';

/// [LocalFilesService] over the sealed format (phase 048): a sealed file is
/// opened under the local-data key, and any other is read as it is.
@LazySingleton(as: LocalFilesService, env: [Environment.dev, Environment.prod, Environment.test])
class LocalFilesServiceImpl implements LocalFilesService {
  LocalFilesServiceImpl(this._vault, this._copies);

  final DeviceVault _vault;
  final TempCopies _copies;

  @override
  Future<Uint8List> read(String path) async {
    final file = File(path);
    final sealed = await SealedReader.open(file);
    if (sealed == null) return file.readAsBytes();
    await _vault.ensureOpen();
    return sealed.readAll();
  }

  @override
  Future<String> openCopy({required String path, required String name}) async {
    await _vault.ensureOpen();
    return _copies.make(source: path, name: name);
  }

  @override
  Future<void> releaseCopy(String copy) => _copies.release(copy);

  @override
  Future<void> saveTo({required String path, required String destination}) async {
    await _vault.ensureOpen();
    await SealedFile.writePlain(from: File(path), to: File(destination));
  }

  @override
  Future<void> clearCopies() => _copies.clear();

  @override
  Future<void> releasePicked(String path) async {
    // A queued message may still send from this very copy: one whose own copy
    // could not be made, or one queued by an older build - and on Android the
    // same document picked again is the same path.
    try {
      final queued = await getIt<OutboxRepository>().pending();
      if (queued.any((entry) => entry.attachment?.localPath == path)) return;
    } catch (_) {
      // A queue that cannot be read could name it: nothing is deleted.
      return;
    }
    await PickerCopies.release(path);
  }

  @override
  Future<void> clearPicked({Set<String> keep = const <String>{}}) => PickerCopies.clear(keep: keep);
}
