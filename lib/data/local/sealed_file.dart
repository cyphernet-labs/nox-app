import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:nox_tor/vault.dart';

/// A file this device keeps sealed (phase 048): a downloaded attachment, one
/// still coming (`.part`), a copy of an outgoing file. The format of the
/// server's files (phase 047) under a key of this device's.
///
/// ```text
/// header (32):  "NOXF" (4) ‖ version 1 (1) ‖ 0 (3) ‖ chunk size, u32 BE: 65536 (4) ‖ file id (16) ‖ 0 (4)
/// chunk i:      the plain bytes [i·64 KiB, min((i+1)·64 KiB, size)), sealed: ciphertext ‖ tag (16)
/// ```
///
/// A chunk is sealed by the vault under the file's own key - drawn from the
/// local-data key and the hex of the file id ([SealedHeader.name]) - with its
/// index and whether it is the last (`NoxVault.sealChunk`). The id is random
/// and lives in the header, so the file opens wherever it is moved or renamed
/// to; a chunk opens only in its own file, at its own place, and as what it
/// was sealed as - a file cut short at a chunk boundary does not read as a
/// shorter file. A file has at least one chunk: an empty one is one empty last
/// chunk, so a file cut back to its header is no empty file either.
///
/// A chunk is sealed once it is whole, the last one once the file is: the
/// nonce of a chunk is its index, so different bytes may never go under an
/// index of an id used before. A download that starts over from the first
/// byte starts a NEW file - a new id; one that goes on from where it stopped
/// seals the same bytes it would have, which reveals nothing.
abstract final class SealedFile {
  const SealedFile._();

  static const int headerLength = 32;
  static const int version = 1;

  /// The plain bytes in a chunk, every one but the last.
  static const int chunkSize = 65536;

  /// A whole chunk on the disk.
  static const int sealedChunkLength = chunkSize + NoxVault.chunkOverhead;

  /// The length of the plain file a sealed file of [fileLength] bytes holds,
  /// or null when no file of this format is that long.
  static int? plainLength(int fileLength) {
    final body = fileLength - headerLength;
    if (body < NoxVault.chunkOverhead) return null;
    final chunks = chunkCount(body);
    final last = body - (chunks - 1) * sealedChunkLength;
    if (last < NoxVault.chunkOverhead) return null;
    return body - chunks * NoxVault.chunkOverhead;
  }

  /// How many chunks a body of [body] bytes, after the header, holds.
  static int chunkCount(int body) => (body + sealedChunkLength - 1) ~/ sealedChunkLength;

  /// The length on the disk of a sealed file of [plainLength] plain bytes.
  static int sealedLength(int plainLength) {
    final chunks = max(1, (plainLength + chunkSize - 1) ~/ chunkSize);
    return headerLength + plainLength + chunks * NoxVault.chunkOverhead;
  }

  /// Whether [file] is one of this format: its header, read. A plain file -
  /// the person's own pick in the composer, or one a build before phase 048
  /// queued - is not; nothing at the start of a picture or a document is this
  /// header.
  static Future<bool> isSealed(File file) async => (await _headerOf(file)) != null;

  /// How much of the part [part] holds, as plain bytes in whole chunks to go
  /// on from - or null when it is no part of this format, and nothing in it
  /// can be gone on from.
  ///
  /// The part is cut back to those chunks: a crash leaves a chunk written
  /// half-way, and a chunk that does not open as one that is not the last is
  /// dropped too - torn by the crash, or the file's own last one, sealed by a
  /// download that finished and did not live to rename the part. Either way
  /// it is asked for again, and it seals the same bytes. Opens one chunk, so
  /// the vault must be open.
  static Future<int?> resumable(File part) async {
    final raf = await part.open(mode: FileMode.append);
    try {
      final length = await raf.length();
      await raf.setPosition(0);
      final header = SealedHeader.parse(await raf.read(headerLength));
      if (header == null) return null;
      var whole = (length - headerLength) ~/ sealedChunkLength;
      if (whole > 0) {
        await raf.setPosition(headerLength + (whole - 1) * sealedChunkLength);
        final sealed = await raf.read(sealedChunkLength);
        try {
          NoxVault.openChunk(header.name, whole - 1, last: false, data: sealed);
        } on VaultException catch (e) {
          if (e.code != VaultCode.forged) rethrow;
          whole--;
        }
      }
      await raf.truncate(headerLength + whole * sealedChunkLength);
      return whole * chunkSize;
    } finally {
      await raf.close();
    }
  }

  /// Writes the plain bytes of [from] to [to] - opened chunk by chunk when it
  /// is sealed, copied as it is when it is not (the person's own file). Each
  /// chunk is written before the next is read, so a large file never sits in
  /// memory whole. A copy that cannot be made in full - no room on the disk, a
  /// chunk that does not open - is deleted before the error goes on: half a
  /// plain file is no file to hand anyone.
  static Future<void> writePlain({required File from, required File to}) async {
    final reader = await SealedReader.open(from);
    if (reader == null) {
      await from.copy(to.path);
      return;
    }
    final raf = await to.open(mode: FileMode.write);
    var written = false;
    try {
      await for (final part in reader.read()) {
        await raf.writeFrom(part);
      }
      await raf.flush();
      written = true;
    } finally {
      await raf.close();
      if (!written && to.existsSync()) await to.delete();
    }
  }

  static Future<SealedHeader?> _headerOf(File file) async {
    final raf = await file.open();
    try {
      return SealedHeader.parse(await raf.read(headerLength));
    } finally {
      await raf.close();
    }
  }
}

/// What a sealed file says about itself before its first chunk.
class SealedHeader {
  SealedHeader._(this.fileId);

  /// A header for a new file: a random id nothing has been sealed under.
  factory SealedHeader.fresh() {
    final random = Random.secure();
    return SealedHeader._(Uint8List.fromList(List<int>.generate(16, (_) => random.nextInt(256))));
  }

  /// The header [bytes] hold, or null when they are not one of this format.
  static SealedHeader? parse(List<int> bytes) {
    if (bytes.length < SealedFile.headerLength) return null;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return null;
    }
    if (bytes[4] != SealedFile.version || bytes[5] != 0 || bytes[6] != 0 || bytes[7] != 0) return null;
    final chunk = (bytes[8] << 24) | (bytes[9] << 16) | (bytes[10] << 8) | bytes[11];
    if (chunk != SealedFile.chunkSize) return null;
    for (var i = 28; i < SealedFile.headerLength; i++) {
      if (bytes[i] != 0) return null;
    }
    return SealedHeader._(Uint8List.fromList(bytes.sublist(12, 28)));
  }

  static const List<int> _magic = <int>[0x4E, 0x4F, 0x58, 0x46]; // NOXF

  /// The random 16 bytes that name the file to the vault.
  final Uint8List fileId;

  /// What the vault draws the file's key from: the id in lowercase hex.
  String get name => fileId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Uint8List encode() {
    final out = Uint8List(SealedFile.headerLength);
    out.setRange(0, 4, _magic);
    out[4] = SealedFile.version;
    out[8] = (SealedFile.chunkSize >> 24) & 0xFF;
    out[9] = (SealedFile.chunkSize >> 16) & 0xFF;
    out[10] = (SealedFile.chunkSize >> 8) & 0xFF;
    out[11] = SealedFile.chunkSize & 0xFF;
    out.setRange(12, 28, fileId);
    return out;
  }
}

/// Why a sealed file could not be read or written.
enum SealedFileError {
  /// Not a file of this format, or not a whole one: its length fits no file of
  /// it, or it changed while it was being read.
  truncated,

  /// More bytes than the file was started for.
  tooLong,
}

/// A sealed file that could not be read or written. Carries its kind and
/// nothing else: a path names the file, and exceptions end up in logs. A chunk
/// that does not open is the vault's own [VaultException].
class SealedFileException implements Exception {
  const SealedFileException(this.error);

  final SealedFileError error;

  @override
  String toString() => 'SealedFileException(${error.name})';
}

/// Reads a sealed file: its plain length, and its plain bytes from any offset.
class SealedReader {
  SealedReader._(this._file, this._header, this.length, this._chunks, this._lastLength);

  /// The file at [file] as one of this format, or null when it is not one: a
  /// plain file. A file of this format that no whole file of it could be -
  /// cut short - is [SealedFileError.truncated].
  static Future<SealedReader?> open(File file) async {
    final raf = await file.open();
    final SealedHeader? header;
    final int fileLength;
    try {
      header = SealedHeader.parse(await raf.read(SealedFile.headerLength));
      fileLength = await raf.length();
    } finally {
      await raf.close();
    }
    if (header == null) return null;
    final length = SealedFile.plainLength(fileLength);
    if (length == null) throw const SealedFileException(SealedFileError.truncated);
    final body = fileLength - SealedFile.headerLength;
    final chunks = SealedFile.chunkCount(body);
    return SealedReader._(file, header, length, chunks, body - (chunks - 1) * SealedFile.sealedChunkLength);
  }

  final File _file;
  final SealedHeader _header;

  /// The plain length of the file.
  final int length;

  final int _chunks;

  /// The last chunk on the disk, its tag included.
  final int _lastLength;

  /// The plain bytes from [from] to the end, a chunk at a time: each read,
  /// opened and handed over before the next is read, so a large file never
  /// sits in memory whole. A chunk that does not open ends the stream with a
  /// [VaultException]; the file read while it changes, with a
  /// [SealedFileException].
  Stream<Uint8List> read({int from = 0}) async* {
    if (from < 0 || from > length) throw RangeError.range(from, 0, length, 'from');
    final first = min(from ~/ SealedFile.chunkSize, _chunks - 1);
    var skip = from - first * SealedFile.chunkSize;
    final raf = await _file.open();
    try {
      await raf.setPosition(SealedFile.headerLength + first * SealedFile.sealedChunkLength);
      for (var index = first; index < _chunks; index++) {
        final last = index == _chunks - 1;
        final want = last ? _lastLength : SealedFile.sealedChunkLength;
        final sealed = await raf.read(want);
        if (sealed.length != want) throw const SealedFileException(SealedFileError.truncated);
        final plain = NoxVault.openChunk(_header.name, index, last: last, data: sealed);
        if (skip >= plain.length) {
          skip -= plain.length;
          continue;
        }
        yield skip == 0 ? plain : Uint8List.sublistView(plain, skip);
        skip = 0;
      }
    } finally {
      await raf.close();
    }
  }

  /// The whole plain file, in memory - a picture to draw, never a copy on the
  /// disk.
  Future<Uint8List> readAll() async {
    final out = Uint8List(length);
    var at = 0;
    await for (final part in read()) {
      out.setRange(at, at + part.length, part);
      at += part.length;
    }
    return out;
  }
}

/// Writes a sealed file chunk by chunk: each one sealed and written once it is
/// whole, each write awaited, the tail held in memory until its chunk is whole
/// or the file is - so what is on the disk is whole chunks, to be gone on from.
class SealedWriter {
  SealedWriter._(this._raf, this._name, this.total, this._index);

  /// Starts a new file at [file], over anything there, under a fresh id: the
  /// header first, flushed, before any chunk. [total] is the plain length the
  /// file will have.
  static Future<SealedWriter> create(File file, {required int total}) async {
    final header = SealedHeader.fresh();
    await file.parent.create(recursive: true);
    final raf = await file.open(mode: FileMode.write);
    try {
      await raf.writeFrom(header.encode());
      await raf.flush();
    } on Object {
      await raf.close();
      rethrow;
    }
    return SealedWriter._(raf, header.name, total, 0);
  }

  /// Goes on with the part [part] from [from] plain bytes - whole chunks, as
  /// [SealedFile.resumable] counted them - towards [total].
  static Future<SealedWriter> append(File part, {required int from, required int total}) async {
    if (from % SealedFile.chunkSize != 0 || from > total) throw ArgumentError.value(from, 'from');
    final raf = await part.open(mode: FileMode.append);
    try {
      await raf.setPosition(0);
      final header = SealedHeader.parse(await raf.read(SealedFile.headerLength));
      if (header == null) throw const SealedFileException(SealedFileError.truncated);
      final index = from ~/ SealedFile.chunkSize;
      final end = SealedFile.headerLength + index * SealedFile.sealedChunkLength;
      if (await raf.length() < end) throw const SealedFileException(SealedFileError.truncated);
      await raf.truncate(end);
      await raf.setPosition(end);
      return SealedWriter._(raf, header.name, total, index);
    } on Object {
      await raf.close();
      rethrow;
    }
  }

  final RandomAccessFile _raf;
  final String _name;

  /// The plain length the file is written towards.
  final int total;

  /// The next chunk to seal.
  int _index;

  final Uint8List _chunk = Uint8List(SealedFile.chunkSize);
  int _filled = 0;
  bool _sealedLast = false;
  bool _closed = false;

  /// The plain bytes taken so far, the tail held in memory included.
  int get written => _index * SealedFile.chunkSize + _filled;

  /// Whether the file is whole: every byte in, the last chunk sealed.
  bool get isComplete => _sealedLast;

  /// Takes [bytes], sealing and writing every chunk they make whole. More
  /// bytes than [total] is [SealedFileError.tooLong], and nothing of them is
  /// taken.
  Future<void> add(List<int> bytes) async {
    if (_closed || _sealedLast) throw StateError('the file is closed');
    if (written + bytes.length > total) throw const SealedFileException(SealedFileError.tooLong);
    var at = 0;
    while (at < bytes.length) {
      final take = min(SealedFile.chunkSize - _filled, bytes.length - at);
      _chunk.setRange(_filled, _filled + take, bytes, at);
      _filled += take;
      at += take;
      if (_filled == SealedFile.chunkSize) await _seal(last: written == total);
    }
  }

  Future<void> _seal({required bool last}) async {
    final sealed = NoxVault.sealChunk(_name, _index, last: last, data: Uint8List.sublistView(_chunk, 0, _filled));
    await _raf.writeFrom(sealed);
    _index++;
    _filled = 0;
    _sealedLast = last;
  }

  /// Ends the writing. Every byte in: the tail is sealed as the last chunk -
  /// an empty file's one empty chunk too - and the file is whole. Short of
  /// that, the tail is let go, and the whole chunks on the disk are what the
  /// next attempt goes on from.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      if (!_sealedLast && written == total) await _seal(last: true);
    } finally {
      await _raf.close();
    }
  }
}
