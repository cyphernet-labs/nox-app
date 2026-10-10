import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/local/app_data_root.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_tor/vault.dart';

/// What opening the local data found at a launch (phase 048).
enum LocalDataOpening {
  /// The key was in the secure store and is in the module now.
  open,

  /// There was neither a key nor a database: a first launch, or the one after
  /// a logout. A new key is in the store and in the module.
  created,

  /// There is no key, and there is a database sealed under one: nothing can
  /// open it any more. The device's data goes, and the device pairs again.
  lost,

  /// The secure store did not answer - a keystore that is not ready yet, an
  /// error of the platform. Nothing is decided on that, and nothing is wiped:
  /// the read is tried again.
  unreadable,
}

/// The local-data key (phase 048): 32 random bytes in the secure store, for
/// this device only, that the database and every file NOX keeps on the disk
/// are sealed under. The module of the channel holds it while the app runs
/// (`NoxVault`); this decides when it gets it.
///
/// Opening never wipes anything by itself: [open] reports what it found, and
/// the start-up (`AuthRepository.openLocalData`) decides - a key that is gone
/// while its data is here costs the data and a new pairing, a store that does
/// not answer costs nothing but a wait. After a logout the key is gone with
/// the data, and the next thing that needs one makes a new one ([ensureOpen]).
@lazySingleton
class DeviceVault {
  DeviceVault(this._session);

  final SessionRepository _session;

  /// Whether the module holds the key this process opened.
  bool get isOpen => _open;
  bool _open = false;

  /// The opening under way: two callers must not each make a key of their own.
  Future<LocalDataOpening>? _opening;

  /// Hands the module the key the secure store holds - or a new one, when the
  /// store has none and there is nothing on the disk a key would have to open.
  Future<LocalDataOpening> open() {
    if (_open) return Future<LocalDataOpening>.value(LocalDataOpening.open);
    return _opening ??= _openOnce().whenComplete(() => _opening = null);
  }

  Future<LocalDataOpening> _openOnce() async {
    final read = await _session.storageKey();
    if (!read.hasData) return LocalDataOpening.unreadable;
    final stored = read.data;
    final key = stored == null ? null : _decode(stored);
    if (key != null) {
      _hand(key);
      return LocalDataOpening.open;
    }
    // A key that does not decode is no key at all: what it sealed is as lost.
    if (await hasLocalData()) return LocalDataOpening.lost;
    final fresh = _mint();
    final saved = await _session.saveStorageKey(key: base64.encode(fresh));
    if (!saved.hasData) {
      fresh.fillRange(0, fresh.length, 0);
      return LocalDataOpening.unreadable;
    }
    _hand(fresh);
    return LocalDataOpening.created;
  }

  /// Opens the vault when it is not open yet. Anything but an open vault - a
  /// key that is gone with its data still here, a store that does not answer
  /// - is [VaultCode.noKey]: nothing may be sealed or opened on a guess.
  Future<void> ensureOpen() async {
    if (_open) return;
    final opening = await open();
    if (opening != LocalDataOpening.open && opening != LocalDataOpening.created) throw const VaultException(VaultCode.noKey);
  }

  /// Drops the key: from the module, then from the secure store (a logout, or
  /// a key that opens nothing). Never throws - a person who chose to sign out
  /// must sign out; a store that keeps a key with nothing left to open costs
  /// nothing, and the next launch replaces it.
  Future<void> forget() async {
    NoxVault.clear();
    _open = false;
    final dropped = await _session.forgetStorageKey();
    if (!dropped.hasData) logRepository.debug(target: this, message: 'vault: the key stayed in the secure store');
  }

  /// Whether the disk holds a database a key would have to open: either
  /// environment's - both are sealed under the one key of this device - or
  /// the compaction file Sembast left of one ([AppDataRoot.databasePaths]).
  /// The wipe deletes exactly these, so a logout in one environment leaves
  /// nothing here that would read as lost data to the other.
  Future<bool> hasLocalData() async {
    for (final path in await AppDataRoot.databasePaths()) {
      if (File(path).existsSync()) return true;
    }
    return false;
  }

  void _hand(Uint8List key) {
    try {
      NoxVault.setKey(key);
    } finally {
      // The module keeps its own copy; this one is not needed any more.
      key.fillRange(0, key.length, 0);
    }
    _open = true;
  }

  /// The stored key, or null when it is not one: not base64, not 32 bytes, or
  /// all zeros, which the module refuses and no real key is.
  static Uint8List? _decode(String stored) {
    try {
      final bytes = base64.decode(stored);
      if (bytes.length != NoxVault.keyLength || bytes.every((b) => b == 0)) return null;
      return bytes;
    } on FormatException {
      return null;
    }
  }

  static Uint8List _mint() {
    final random = Random.secure();
    final key = Uint8List(NoxVault.keyLength);
    do {
      for (var i = 0; i < key.length; i++) {
        key[i] = random.nextInt(256);
      }
    } while (key.every((b) => b == 0));
    return key;
  }
}
