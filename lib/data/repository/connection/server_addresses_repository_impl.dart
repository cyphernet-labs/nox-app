import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/repository/connection/connection_storage.dart';
import 'package:nox_app/domain/model/connection/server_addresses.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';

/// The server's addresses in secure storage (phase 040). Secure rather than
/// prefs: the onion address lets anyone who has it ask the Tor network whether
/// this person's server is online.
@LazySingleton(as: ServerAddressesRepository, env: [Environment.dev, Environment.prod, Environment.test])
class ServerAddressesRepositoryImpl with BaseRepositoryHelper implements ServerAddressesRepository {
  ServerAddressesRepositoryImpl(this._storage);

  final FlutterSecureStorage _storage;

  /// Writes are read-modify-write; two in flight (a greeting and a successful
  /// direct connection) would otherwise lose one of them.
  Future<void> _writes = Future<void>.value();

  /// Every value written, after it is on disk.
  final StreamController<ServerAddresses> _changes = StreamController<ServerAddresses>.broadcast();

  @override
  Future<RepositoryResult<ServerAddresses>> read() {
    return execute<ServerAddresses>(() async => RepositoryResult<ServerAddresses>.success(data: await _read()));
  }

  @override
  Future<RepositoryResult<bool>> saveFromServer({required List<String> direct, required String? onion}) {
    return execute<bool>(() async {
      await _serialised(() async {
        final current = await _read();
        final next = current.copyWith(direct: List<String>.unmodifiable(direct), onion: onion);
        if (next == current) return;
        await _write(next);
      });
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  Future<RepositoryResult<bool>> recordLastGood(String address) {
    return execute<bool>(() async {
      await _serialised(() async {
        final current = await _read();
        if (current.lastGood == address) return;
        await _write(current.copyWith(lastGood: address));
      });
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  Future<RepositoryResult<bool>> clear() {
    return execute<bool>(() async {
      await _serialised(() => _storage.delete(key: ConnectionStorage.serverAddresses));
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  Stream<ServerAddresses> watch() {
    StreamSubscription<ServerAddresses>? changes;
    late final StreamController<ServerAddresses> controller;
    controller = StreamController<ServerAddresses>(
      onListen: () async {
        // Subscribed BEFORE the first read, so a write landing in between is
        // not lost: at worst the same value arrives twice.
        changes = _changes.stream.listen(controller.add);
        try {
          controller.add(await _read());
        } on Object catch (e, st) {
          controller.addError(e, st);
        }
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  Future<void> _serialised(Future<void> Function() body) {
    final next = _writes.then((_) => body());
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<ServerAddresses> _read() async {
    final raw = await _storage.read(key: ConnectionStorage.serverAddresses);
    if (raw == null || raw.isEmpty) return ServerAddresses.empty;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return ServerAddresses.empty;
      final direct = json['direct'];
      return ServerAddresses(
        direct: direct is List ? List<String>.unmodifiable(direct.whereType<String>()) : const <String>[],
        onion: json['onion'] is String ? json['onion'] as String : null,
        lastGood: json['last_good'] is String ? json['last_good'] as String : null,
      );
    } on FormatException {
      // A record this build cannot read is a record it does not have; the next
      // greeting writes a good one.
      return ServerAddresses.empty;
    }
  }

  Future<void> _write(ServerAddresses addresses) async {
    await _storage.write(
      key: ConnectionStorage.serverAddresses,
      value: jsonEncode(<String, dynamic>{'direct': addresses.direct, 'onion': addresses.onion, 'last_good': addresses.lastGood}),
    );
    _changes.add(addresses);
  }
}
