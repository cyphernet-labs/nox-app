import 'package:injectable/injectable.dart';
import 'package:nox_app/data/service/file/system_save_dialog.dart';
import 'package:nox_app/domain/service/file_picker_service.dart';
import 'package:nox_app/domain/service/file_save_service.dart';
import 'package:nox_app/domain/service/local_files_service.dart';

/// [FileSaveService] through the save dialog each platform has.
///
/// The desktops' (file_selector) names a place, and the plain file is written
/// there a chunk at a time. iOS and Android have no such dialog in
/// file_selector: its `getSaveLocation` is not implemented there, and the
/// plugin's error read as a cancel, so Save did nothing at all. Their own
/// dialog ([SystemSaveDialog]) takes a FILE, so a plain copy is made first -
/// what NOX keeps is sealed (phase 048) - handed to it, and deleted whatever
/// the answer: by then the platform has written it where the person chose.
@LazySingleton(as: FileSaveService, env: [Environment.dev, Environment.prod, Environment.test])
class FileSaveServiceImpl implements FileSaveService {
  FileSaveServiceImpl(this._picker, this._files, this._dialog);

  final FilePickerService _picker;
  final LocalFilesService _files;
  final SystemSaveDialog _dialog;

  @override
  Future<bool> save({required String path, required String name}) async {
    if (_dialog.isAvailable) {
      final copy = await _files.openCopy(path: path, name: name);
      try {
        return await _dialog.save(path: copy);
      } finally {
        await _files.releaseCopy(copy);
      }
    }
    final destination = await _picker.pickSaveLocation(suggestedName: name);
    if (destination == null) return false;
    await _files.saveTo(path: path, destination: destination);
    return true;
  }
}
