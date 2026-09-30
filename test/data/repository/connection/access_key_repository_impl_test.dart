import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/repository/connection/access_key_repository_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccessKeyRepositoryImpl repository;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    repository = AccessKeyRepositoryImpl(const FlutterSecureStorage());
  });

  test('the device key is minted once and then read back unchanged', () async {
    final first = (await repository.deviceKey()).data!;
    final again = (await repository.deviceKey()).data!;
    expect(first.privateKey, hasLength(32));
    expect(first.publicKey, hasLength(32));
    expect(again.privateKey, first.privateKey);
    expect(again.publicKey, first.publicKey);
    expect(first.publicBase64, hasLength(44));
  });

  test('the public half is the x25519 public key of the private half', () async {
    final pair = (await repository.deviceKey()).data!;
    final derived = await (await X25519().newKeyPairFromSeed(pair.privateKey)).extractPublicKey();
    expect(Uint8List.fromList(derived.bytes), pair.publicKey);
  });

  test('regenerating gives a different key and forgets the registration', () async {
    final first = (await repository.deviceKey()).data!;
    await repository.markRegistered(true);
    expect((await repository.isRegistered()).data, isTrue);
    final next = (await repository.regenerate()).data!;
    expect(next.publicKey, isNot(first.publicKey));
    expect((await repository.isRegistered()).data, isFalse);
    expect((await repository.deviceKey()).data!.publicKey, next.publicKey);
  });

  test('the stored key is read without minting one', () async {
    expect((await repository.storedDeviceKey()).data, isNull);
    expect((await repository.storedDeviceKey()).data, isNull, reason: 'reading twice created nothing');

    final minted = (await repository.deviceKey()).data!;
    expect((await repository.storedDeviceKey()).data!.publicKey, minted.publicKey);
  });
}
