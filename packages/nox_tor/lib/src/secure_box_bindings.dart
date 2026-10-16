// The C ABI of RustSecureBox in the module (specs/050-rust-secure-box/
// contracts/ffi-box.md): the four functions of the library the channel check
// runs on.
//
// Part of the one library the build hook builds, whose asset id is named after
// nox_tor_bindings.dart - hence the default asset of this library. Every
// function is synchronous and short, and none calls back into Dart, hence
// isLeaf.
@DefaultAsset('package:nox_tor/src/nox_tor_bindings.dart')
library;

import 'dart:ffi';

@Native<Int32 Function(Pointer<Uint8>, Pointer<Uint8>)>(symbol: 'nox_box_generate_keys', isLeaf: true)
external int noxBoxGenerateKeys(Pointer<Uint8> privateOut, Pointer<Uint8> publicOut);

@Native<Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)>(symbol: 'nox_box_get_challenge', isLeaf: true)
external int noxBoxGetChallenge(Pointer<Uint8> privateKey, Pointer<Uint8> challengeOut, Pointer<Uint8> publicOut);

@Native<Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)>(symbol: 'nox_box_sign_challenge', isLeaf: true)
external int noxBoxSignChallenge(Pointer<Uint8> privateKey, Pointer<Uint8> challenge, Pointer<Uint8> signatureOut);

@Native<Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)>(symbol: 'nox_box_check_signature', isLeaf: true)
external int noxBoxCheckSignature(Pointer<Uint8> publicKey, Pointer<Uint8> challenge, Pointer<Uint8> signature);
