import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/repository/connection/connection_storage.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/connection/access_key_repository.dart';

/// This device's onion access key (phase 040).
///
/// x25519 from `cryptography`, generated here and kept here: the private half
/// is written with [ConnectionStorage]'s key options, so no backup restores it
/// on another phone, and the server would refuse it anyway as somebody else's
/// key (039).
@LazySingleton(as: AccessKeyRepository, env: [Environment.dev, Environment.prod, Environment.test])
class AccessKeyRepositoryImpl with BaseRepositoryHelper implements AccessKeyRepository {
  AccessKeyRepositoryImpl(this._storage);

  final FlutterSecureStorage _storage;
  final X25519 _x25519 = X25519();

  @override
  Future<RepositoryResult<AccessKeyPair>> deviceKey() {
    return execute<AccessKeyPair>(() async {
      final stored = await _storage.read(
        key: ConnectionStorage.accessKey,
        iOptions: ConnectionStorage.keyIOSOptions,
        mOptions: ConnectionStorage.keyMacOsOptions,
      );
      final private = _decode32(stored);
      if (private != null) return RepositoryResult<AccessKeyPair>.success(data: await _pairFrom(private));
      return RepositoryResult<AccessKeyPair>.success(data: await _mint());
    });
  }

  @override
  Future<RepositoryResult<AccessKeyPair?>> storedDeviceKey() {
    return execute<AccessKeyPair?>(() async {
      final private = _decode32(
        await _storage.read(
          key: ConnectionStorage.accessKey,
          iOptions: ConnectionStorage.keyIOSOptions,
          mOptions: ConnectionStorage.keyMacOsOptions,
        ),
      );
      return RepositoryResult<AccessKeyPair?>.success(data: private == null ? null : await _pairFrom(private));
    });
  }

  @override
  Future<RepositoryResult<AccessKeyPair>> regenerate() {
    return execute<AccessKeyPair>(() async {
      final pair = await _mint();
      await _storage.delete(key: ConnectionStorage.accessKeyRegistered);
      return RepositoryResult<AccessKeyPair>.success(data: pair);
    });
  }

  @override
  Future<RepositoryResult<bool>> isRegistered() {
    return execute<bool>(() async {
      final flag = await _storage.read(key: ConnectionStorage.accessKeyRegistered);
      return RepositoryResult<bool>.success(data: flag == '1');
    });
  }

  @override
  Future<RepositoryResult<bool>> markRegistered(bool registered) {
    return execute<bool>(() async {
      if (registered) {
        await _storage.write(key: ConnectionStorage.accessKeyRegistered, value: '1');
      } else {
        await _storage.delete(key: ConnectionStorage.accessKeyRegistered);
      }
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  Future<AccessKeyPair> _mint() async {
    final pair = await _x25519.newKeyPair();
    final private = Uint8List.fromList(await pair.extractPrivateKeyBytes());
    final public = Uint8List.fromList((await pair.extractPublicKey()).bytes);
    await _storage.write(
      key: ConnectionStorage.accessKey,
      value: base64Encode(private),
      iOptions: ConnectionStorage.keyIOSOptions,
      mOptions: ConnectionStorage.keyMacOsOptions,
    );
    return AccessKeyPair(privateKey: private, publicKey: public);
  }

  Future<AccessKeyPair> _pairFrom(Uint8List private) async {
    final pair = await _x25519.newKeyPairFromSeed(private);
    final public = Uint8List.fromList((await pair.extractPublicKey()).bytes);
    return AccessKeyPair(privateKey: private, publicKey: public);
  }

  static Uint8List? _decode32(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    try {
      final bytes = base64Decode(stored);
      return bytes.length == 32 ? Uint8List.fromList(bytes) : null;
    } on FormatException {
      return null;
    }
  }
}
