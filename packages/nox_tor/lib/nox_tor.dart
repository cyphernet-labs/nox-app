/// The embedded Tor client of the NOX app (phase 040), as Dart sees it.
///
/// A thin, synchronous wrapper over the C ABI: every call returns at once, and
/// the work happens on the client's own runtime. The app never uses this
/// directly - it goes through its `TorService`, which a test environment
/// replaces with a fake, so widget and BLoC tests never load the library.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/nox_tor_bindings.dart';

/// `NoxTorStatus.state`.
enum NoxTorState { stopped, bootstrapping, ready, dormant, failed, obsolete }

/// `NoxTorStatus.error` - the last failure, as a kind and never as text.
///
/// [missingClientAuth] and [wrongClientAuth] keep their places in the ABI's
/// numbering and are never produced since phase 045: the client holds no
/// onion access keys.
enum NoxTorError { none, missingClientAuth, wrongClientAuth, timeout, network, internal, softwareDeprecated }

/// One status snapshot.
///
/// `NoxTorStatus.port` of the ABI is not read: it was the loopback bridge's,
/// and there is no bridge any more (phase 044) - a connection through Tor is
/// a channel of `package:nox_tor/channel.dart`.
class NoxTorSnapshot {
  const NoxTorSnapshot({required this.state, required this.bootstrapPercent, required this.error});

  final NoxTorState state;
  final int bootstrapPercent;
  final NoxTorError error;

  static const NoxTorSnapshot stopped = NoxTorSnapshot(state: NoxTorState.stopped, bootstrapPercent: 0, error: NoxTorError.none);

  @override
  String toString() => 'NoxTorSnapshot(${state.name}, $bootstrapPercent%, ${error.name})';
}

/// A C ABI call that did not succeed. Carries the code only: a message could
/// name the onion service.
class NoxTorException implements Exception {
  const NoxTorException(this.code);

  final int code;

  @override
  String toString() => 'NoxTorException($code)';
}

abstract final class NoxTor {
  static bool? _supported;

  /// Whether the native module loaded. It is built on all five platforms
  /// (phase 044: the secure channel needs it everywhere), and Tor is offered
  /// on all five since phase 045.
  static bool get isSupported => _supported ??= _probe();

  static bool _probe() {
    try {
      noxTorVersion();
      return true;
    } catch (_) {
      return false;
    }
  }

  static String get version => noxTorVersion().toDartString();

  static void start({required String stateDir, required String cacheDir}) {
    _check(using((arena) => noxTorStart(stateDir.toNativeUtf8(allocator: arena), cacheDir.toNativeUtf8(allocator: arena))));
  }

  static void stop() => noxTorStop();

  static void setDormant(bool dormant) => noxTorSetDormant(dormant);

  static NoxTorSnapshot status() => using((arena) {
    final out = arena<NoxTorStatusStruct>();
    _check(noxTorStatus(out));
    final s = out.ref;
    return NoxTorSnapshot(
      state: NoxTorState.values[s.state.clamp(0, NoxTorState.values.length - 1)],
      bootstrapPercent: s.bootstrapPercent,
      error: NoxTorError.values[s.error.clamp(0, NoxTorError.values.length - 1)],
    );
  });

  /// The `<56>.onion` address of a v3 onion service's public key.
  static String onionFromPublicKey(Uint8List publicKey) {
    if (publicKey.length != 32) throw ArgumentError.value(publicKey.length, 'publicKey', 'must be 32 bytes');
    return using((arena) {
      final pub = arena<Uint8>(32);
      pub.asTypedList(32).setAll(0, publicKey);
      final out = arena<Uint8>(64).cast<Utf8>();
      _check(noxTorOnionFromPubkey(pub, out, 64));
      return out.toDartString();
    });
  }

  static void _check(int code) {
    if (code != 0) throw NoxTorException(code);
  }
}
