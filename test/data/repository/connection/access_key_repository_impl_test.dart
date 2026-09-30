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

  test('an invite lends an onion address and a one-time key until cleared', () async {
    expect((await repository.invite()).data, isNull);
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
    await repository.saveInvite(onion: 'abc.onion:443', oneTimeKey: key);
    final invite = (await repository.invite()).data!;
    expect(invite.onion, 'abc.onion:443');
    expect(invite.oneTimeKey, key);
    await repository.clearInvite();
    expect((await repository.invite()).data, isNull);
  });
}
