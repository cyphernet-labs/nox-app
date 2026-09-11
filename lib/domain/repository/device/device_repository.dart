import 'package:nox_app/domain/model/device/device_model.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// The devices authorised to speak as this person, and the ability to cut one
/// off. Server-only: nothing here is cached, because a stale list would offer
/// to revoke something that is already gone.
abstract interface class DeviceRepository {
  Future<RepositoryResult<List<DeviceModel>>> getDevices();

  /// Removes a key from the allowed list. Revoking a key that is not there is
  /// a success: the caller asked for a state and that state holds.
  Future<RepositoryResult<bool>> revoke({required String deviceKey});

  /// Mints an invite and returns the link to show. Lives ten minutes.
  Future<RepositoryResult<String>> inviteDevice();

  /// Fires when the set of devices has changed on the server — today, when
  /// another device has just been paired.
  ///
  /// A signal, not a value: there is nothing to carry, because the receiver
  /// re-reads the list rather than patching it. That follows from this
  /// repository never caching — the server is the only authority on who may
  /// speak as this person, and a list assembled from event payloads would be a
  /// second one.
  ///
  /// LIVE, not durable: a device that was offline when it happened hears
  /// nothing, and nothing replays it afterwards. That is survivable rather than
  /// harmless. A device that comes BACK to this screen reads the list from the
  /// server and sees the truth at once; a screen that was already open when the
  /// channel dropped is the case this signal cannot reach, and it is covered
  /// instead by re-reading when the channel returns.
  ///
  /// It can also fire when nothing changed: a device whose `pair` reply was
  /// lost retries with the same token, and the server announces again. Nothing
  /// is carried and the answer is a re-read, so a repeat costs one list read
  /// and says the same true thing twice.
  Stream<void> watchDeviceListChanged();

  /// Sends the person's new name to the server.
  ///
  /// It lives here rather than on the session repository because the session
  /// repository is local storage, and this is a wire command — contract §8A
  /// groups the name with the devices for the same reason: both describe the
  /// identity as the server holds it.
  Future<RepositoryResult<bool>> setLabel({required String label});
}
