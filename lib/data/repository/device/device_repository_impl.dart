import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/domain/model/device/device_model.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/device/device_repository.dart';
import 'package:nox_app/general/pairing/device_keys.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';

/// Devices over the live socket (contract §8A).
///
/// Deliberately NOT cache-first, unlike chats and messages: a stale list would
/// offer to revoke a device that is already gone, and show one that was added
/// from elsewhere as missing. The list is short and read rarely, so asking the
/// server every time costs nothing worth saving.
@LazySingleton(as: DeviceRepository, env: [Environment.dev])
class DeviceRepositoryImpl with BaseRepositoryHelper implements DeviceRepository {
  DeviceRepositoryImpl(this._socket, this._session);

  final NoxSocketClient _socket;
  final SessionRepository _session;

  @override
  Future<RepositoryResult<List<DeviceModel>>> getDevices() {
    return execute<List<DeviceModel>>(() async {
      final reply = await _socket.send('device.list', const <String, dynamic>{});
      if (!reply.ok) throw RepositoryException.fromWireCode(reply.errorCode ?? '');

      // Which row is "this device" is known only here: the server sees a key,
      // not a person holding a phone.
      final seed = await _session.deviceSecret();
      final own = seed.hasData ? await DeviceKeys.publicKey(seed.data!) : null;

      final raw = reply.data?['devices'];
      final devices = <DeviceModel>[];
      if (raw is List) {
        for (final entry in raw) {
          if (entry is! Map<String, dynamic>) continue;
          final key = entry['device_key'] as String? ?? '';
          devices.add(
            DeviceModel(
              deviceKey: key,
              platform: entry['platform'] as String? ?? '',
              pairedAt: _seconds(entry['created_at']),
              lastSeenAt: _seconds(entry['last_seen_at']),
              isCurrent: own != null && key == own,
            ),
          );
        }
      }
      return RepositoryResult<List<DeviceModel>>.success(data: devices);
    });
  }

  @override
  Future<RepositoryResult<bool>> revoke({required String deviceKey}) {
    return execute<bool>(() async {
      final reply = await _socket.send('device.revoke', <String, dynamic>{'device_key': deviceKey});
      if (!reply.ok) throw RepositoryException.fromWireCode(reply.errorCode ?? '');
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  Future<RepositoryResult<String>> inviteDevice() {
    return execute<String>(() async {
      final reply = await _socket.send('device.invite', const <String, dynamic>{});
      if (!reply.ok) throw RepositoryException.fromWireCode(reply.errorCode ?? '');
      final link = reply.data?['link'] as String? ?? '';
      if (link.isEmpty) throw RepositoryException.internal;
      return RepositoryResult<String>.success(data: link);
    });
  }

  @override
  Future<RepositoryResult<bool>> setLabel({required String label}) {
    return execute<bool>(() async {
      final reply = await _socket.send('identity.setLabel', <String, dynamic>{'label': label});
      if (!reply.ok) throw RepositoryException.fromWireCode(reply.errorCode ?? '');
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  static DateTime _seconds(Object? value) => DateTime.fromMillisecondsSinceEpoch((value is int ? value : 0) * 1000, isUtc: true).toLocal();
}
