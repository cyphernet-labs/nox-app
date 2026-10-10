import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_windows/path_provider_windows.dart';

/// Where this device keeps what NOX keeps (phase 048): the database, the
/// attachments, the outgoing queue's copies of the files it sends and the Tor
/// client's state.
///
/// The application's own data folder, never "Documents": iOS backs Documents
/// up to iCloud and desktops hand it to whatever syncs it, and nothing here is
/// worth a backup - the conversation comes back from the server once the
/// device is paired again. On iOS and macOS the folder is also marked as not
/// for backups ([excludeFromBackup]); on Android the manifest turns backups
/// and device-to-device transfer off; on Windows the folder is the LOCAL
/// application data, which a roaming profile does not carry
/// ([useLocalFolderOnWindows]).
abstract final class AppDataRoot {
  const AppDataRoot._();

  /// Downloaded attachments, finished and half-way (phases 028, 043), sealed.
  static const String attachmentsFolder = 'nox_attachments';

  /// The outgoing queue's copies of the files it sends (phase 043), sealed.
  static const String outboxFolder = 'nox_outbox';

  /// The database files, one per environment that keeps one on disk. A key
  /// that is gone while one of these is here means data nothing can open any
  /// more (`DeviceVault`).
  static const List<String> databaseFiles = <String>['app.db', 'app_dev.db'];

  /// The folder under `%LOCALAPPDATA%` on Windows.
  static const String windowsFolder = 'NOX';

  /// The data folder: path_provider's application support folder - on Windows
  /// once [useLocalFolderOnWindows] has pointed it at `%LOCALAPPDATA%\NOX`.
  static Future<Directory> directory() => getApplicationSupportDirectory();

  /// [name] inside the data folder.
  static Future<String> pathOf(String name) async => '${(await directory()).path}${Platform.pathSeparator}$name';

  /// Points the application support folder at `%LOCALAPPDATA%\NOX` on Windows,
  /// for every caller of path_provider - the secure store's own file among them.
  ///
  /// path_provider answers that question on Windows with the ROAMING
  /// application data, which a roaming profile copies to a server and onto
  /// every machine the person signs in to; flutter_secure_storage keeps its
  /// one file there and has no option to put it anywhere else. Called first
  /// thing in `main`, before anything asks for a folder.
  static void useLocalFolderOnWindows() {
    if (Platform.isWindows) PathProviderPlatform.instance = LocalAppDataPathProvider();
  }

  static const MethodChannel _backup = MethodChannel('nox/backup');

  /// Marks the data folder as not for backups: iCloud and a backup to a
  /// computer on iOS, Time Machine on macOS (FR-010). The runner sets the
  /// folder's `isExcludedFromBackup`; set at every launch, because the mark is
  /// a property of the folder and a folder made again after a wipe is a new
  /// one. Elsewhere the platform needs nothing of the kind.
  ///
  /// Best effort: a launch does not wait on a backup that may never happen,
  /// and a runner that refuses is logged, not thrown.
  static Future<void> excludeFromBackup() async {
    if (!Platform.isIOS && !Platform.isMacOS) return;
    try {
      final dir = await directory();
      await dir.create(recursive: true);
      await _backup.invokeMethod<bool>('exclude', <String, Object>{'path': dir.path});
    } on Object catch (error) {
      // The type only: a platform error may quote the path.
      logRepository.error(target: 'AppDataRoot', error: error.runtimeType);
    }
  }

  /// Deletes what builds before phase 048 kept unsealed, where it is safe to
  /// say it is theirs: their database in "Documents" - backed up to iCloud on
  /// iOS - on the platforms where Documents is the app's own folder (iOS,
  /// Android, and macOS when the folder lies in the sandbox's container); their attachments in the cache folder,
  /// which is the app's own everywhere; and on Windows what they kept in the
  /// roaming folder. On Windows and Linux "Documents" is the person's own, and
  /// a file named `app.db` there is not certainly this app's to delete.
  ///
  /// Settled on the first launch after the update; every launch after it finds
  /// nothing. Best effort, like every delete of a wipe.
  static Future<void> sweepLegacy() async {
    try {
      final root = await directory();
      if (Platform.isIOS || Platform.isAndroid || Platform.isMacOS) {
        final documents = await getApplicationDocumentsDirectory();
        if (documents.path != root.path && _isOwnDocuments(documents.path)) {
          for (final name in databaseFiles) {
            await _delete(File('${documents.path}${Platform.pathSeparator}$name'));
          }
        }
      }
      final cache = await getApplicationCacheDirectory();
      if (cache.path != root.path) await _delete(Directory('${cache.path}${Platform.pathSeparator}$attachmentsFolder'));
      if (Platform.isWindows) {
        // The roaming folder those builds wrote to: the secure store's file,
        // the queue's copies, the Tor client's state.
        final roaming = await PathProviderWindows().getApplicationSupportPath();
        if (roaming != null && roaming != root.path) {
          await _delete(File('$roaming\\flutter_secure_storage.dat'));
          await _delete(Directory('$roaming\\$outboxFolder'));
          await _delete(Directory('$roaming\\nox_tor_state'));
        }
      }
    } on Object catch (error) {
      logRepository.error(target: 'AppDataRoot', error: error.runtimeType);
    }
  }

  /// Whether [documents] is the app's own folder: always on iOS and Android;
  /// on macOS only inside the sandbox's container - a build that runs outside
  /// the sandbox is handed the person's own Documents.
  static bool _isOwnDocuments(String documents) => !Platform.isMacOS || isMacContainerPath(documents);

  /// Whether [path] lies in a macOS sandbox container.
  @visibleForTesting
  static bool isMacContainerPath(String path) => path.contains('/Library/Containers/');

  static Future<void> _delete(FileSystemEntity entity) async {
    try {
      if (entity.existsSync()) await entity.delete(recursive: true);
    } on FileSystemException catch (error) {
      logRepository.error(target: 'AppDataRoot', error: error.runtimeType);
    }
  }
}

/// path_provider on Windows with the application support folder moved to
/// `%LOCALAPPDATA%\NOX` (phase 048). Every other folder is the plugin's own.
class LocalAppDataPathProvider extends PathProviderWindows {
  LocalAppDataPathProvider({@visibleForTesting this._localAppData});

  /// `FOLDERID_LocalAppData`. Named by its id rather than through
  /// `WindowsKnownFolder`, which the analyzer resolves to the plugin's stub.
  static const String localAppDataFolder = '{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}';

  final Future<String?> Function()? _localAppData;

  @override
  Future<String?> getApplicationSupportPath() async {
    final local = await (_localAppData?.call() ?? getPath(localAppDataFolder));
    if (local == null || local.isEmpty) return null;
    final dir = Directory('$local${Platform.pathSeparator}${AppDataRoot.windowsFolder}');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir.path;
  }
}
