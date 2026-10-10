import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/local/sealed_file.dart';
import 'package:nox_tor/vault.dart';

const int _chunk = SealedFile.chunkSize;

void main() {
  late Directory dir;

  setUp(() async {
    NoxVault.setKey(Uint8List.fromList(List<int>.generate(32, (i) => 0x21 + i)));
    dir = await Directory.systemTemp.createTemp('nox_sealed');
  });

  tearDown(() async {
    NoxVault.clear();
    await dir.delete(recursive: true);
  });

  /// [length] bytes that differ from chunk to chunk, a marker at the start.
  Uint8List plain(int length) {
    final bytes = Uint8List.fromList(List<int>.generate(length, (i) => (i * 31 + i ~/ _chunk) & 0xFF));
    final marker = utf8.encode('NOX-MARKER');
    if (length >= marker.length) bytes.setRange(0, marker.length, marker);
    return bytes;
  }

  /// Writes [data] in pieces of [piece] bytes, as a download hands them over.
  Future<File> seal(Uint8List data, {String name = 'f', int piece = 7001}) async {
    final file = File('${dir.path}/$name');
    final writer = await SealedWriter.create(file, total: data.length);
    for (var at = 0; at < data.length; at += piece) {
      await writer.add(data.sublist(at, at + piece > data.length ? data.length : at + piece));
    }
    await writer.close();
    expect(writer.isComplete, isTrue);
    return file;
  }

  Future<Uint8List> readAll(File file) async => (await SealedReader.open(file))!.readAll();

  group('the header', () {
    test('says NOXF, version 1, chunks of 64 KiB, a random id, and nothing else', () {
      final header = SealedHeader.fresh();
      final bytes = header.encode();

      expect(bytes, hasLength(32));
      expect(ascii.decode(bytes.sublist(0, 4)), 'NOXF');
      expect(bytes[4], 1);
      expect(bytes.sublist(5, 8), [0, 0, 0]);
      expect(bytes.sublist(8, 12), [0, 1, 0, 0], reason: '65536, big-endian');
      expect(bytes.sublist(28), [0, 0, 0, 0]);
      expect(SealedHeader.parse(bytes)!.name, header.name);
      expect(header.name, matches(RegExp(r'^[0-9a-f]{32}$')), reason: 'the hex of the id is what the vault keys the file by');
      expect(SealedHeader.fresh().name, isNot(header.name));
    });

    test('anything else is not one: another version, another chunk size, a reserved byte set, a picture', () {
      final good = SealedHeader.fresh().encode();
      for (final at in [0, 4, 6, 10, 30]) {
        final changed = Uint8List.fromList(good)..[at] ^= 0x01;
        expect(SealedHeader.parse(changed), isNull, reason: 'byte $at');
      }
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List<int>.filled(24, 0)]);
      expect(SealedHeader.parse(png), isNull);
      expect(SealedHeader.parse(good.sublist(0, 31)), isNull);
    });
  });

  test('a length on the disk is the plain length of exactly one file, or of none', () {
    for (final length in [0, 1, _chunk - 1, _chunk, _chunk + 1, 3 * _chunk, 3 * _chunk + 5]) {
      expect(SealedFile.plainLength(SealedFile.sealedLength(length)), length, reason: '$length');
    }
    // Shorter than its one chunk's tag; a last chunk shorter than a tag.
    expect(SealedFile.plainLength(32), isNull);
    expect(SealedFile.plainLength(32 + 15), isNull);
    expect(SealedFile.plainLength(32 + SealedFile.sealedChunkLength + 5), isNull);
  });

  group('written and read', () {
    for (final length in [0, 1, _chunk - 1, _chunk, _chunk + 1, 2 * _chunk + 123]) {
      test('$length bytes go round, from any offset', () async {
        final data = plain(length);
        final file = await seal(data);

        expect(file.lengthSync(), SealedFile.sealedLength(length));
        final reader = (await SealedReader.open(file))!;
        expect(reader.length, length);
        expect(await reader.readAll(), data);
        for (final from in {0, 1, _chunk - 1, _chunk, _chunk + 7, length ~/ 2, length}) {
          if (from > length) continue;
          final parts = await reader.read(from: from).toList();
          expect(parts.expand((p) => p).toList(), data.sublist(from), reason: 'from $from');
        }
      });
    }

    test('nothing of the plain bytes is on the disk, and the same bytes sealed twice are two different files', () async {
      final data = plain(3 * _chunk);
      final first = (await seal(data, name: 'a')).readAsBytesSync();
      final second = (await seal(data, name: 'b')).readAsBytesSync();

      expect(latin1.decode(first), isNot(contains('NOX-MARKER')));
      expect(first.sublist(32), isNot(second.sublist(32)), reason: 'a fresh id: another key for every file');
    });

    test('a plain file is no sealed one, and is read by whoever asked as it is', () async {
      final file = File('${dir.path}/photo.png')..writeAsBytesSync(plain(100));

      expect(await SealedFile.isSealed(file), isFalse);
      expect(await SealedReader.open(file), isNull);
    });

    test('moved and renamed it still opens: the id is in the header, not in the path', () async {
      final data = plain(_chunk + 9);
      final file = await seal(data);
      final moved = await file.rename('${dir.path}/elsewhere.mp4');

      expect(await readAll(moved), data);
    });
  });

  group('changed on the disk, it does not read as another file', () {
    Future<void> expectForged(File file) async {
      await expectLater(readAll(file), throwsA(isA<VaultException>().having((e) => e.code, 'code', VaultCode.forged)));
    }

    test('a bit flipped in a chunk', () async {
      final file = await seal(plain(2 * _chunk + 10));
      final bytes = file.readAsBytesSync()..[32 + SealedFile.sealedChunkLength + 100] ^= 0x04;
      file.writeAsBytesSync(bytes);

      // The chunk before it still opens, and its bytes come first.
      final reader = (await SealedReader.open(file))!;
      final heard = <int>[];
      await expectLater(reader.read().forEach((p) => heard.addAll(p)), throwsA(isA<VaultException>()));
      expect(heard, hasLength(_chunk));
    });

    test('cut at a chunk boundary: its new end was not sealed as the last', () async {
      final file = await seal(plain(3 * _chunk));
      final bytes = file.readAsBytesSync();
      file.writeAsBytesSync(bytes.sublist(0, 32 + 2 * SealedFile.sealedChunkLength));

      await expectForged(file);
    });

    test('cut inside a chunk: no file of the format is that long, or its last chunk does not open', () async {
      final file = await seal(plain(3 * _chunk));
      final bytes = file.readAsBytesSync();
      file.writeAsBytesSync(bytes.sublist(0, 32 + 2 * SealedFile.sealedChunkLength + 10));
      await expectLater(SealedReader.open(file), throwsA(isA<SealedFileException>()));

      file.writeAsBytesSync(bytes.sublist(0, 32 + 2 * SealedFile.sealedChunkLength + 500));
      await expectForged(file);
    });

    test('two chunks swapped', () async {
      final file = await seal(plain(3 * _chunk));
      final bytes = file.readAsBytesSync();
      const a = 32;
      const b = 32 + SealedFile.sealedChunkLength;
      final first = bytes.sublist(a, b);
      bytes.setRange(a, b, bytes.sublist(b, b + SealedFile.sealedChunkLength));
      bytes.setRange(b, b + SealedFile.sealedChunkLength, first);
      file.writeAsBytesSync(bytes);

      await expectForged(file);
    });

    test("a chunk of another file, at the same place", () async {
      final one = await seal(plain(2 * _chunk), name: 'one');
      final other = await seal(plain(2 * _chunk), name: 'other');
      final bytes = one.readAsBytesSync();
      bytes.setRange(32, 32 + SealedFile.sealedChunkLength, other.readAsBytesSync().sublist(32));
      one.writeAsBytesSync(bytes);

      await expectForged(one);
    });

    test('under another key', () async {
      final file = await seal(plain(10));
      NoxVault.setKey(Uint8List.fromList(List<int>.generate(32, (i) => 0x90 + i)));

      await expectForged(file);
    });
  });

  group('a part, gone on with (phase 043)', () {
    test('an interrupted file keeps its whole chunks, and goes on from the last of them', () async {
      final data = plain(3 * _chunk + 500);
      final part = File('${dir.path}/f.part');
      final writer = await SealedWriter.create(part, total: data.length);
      await writer.add(data.sublist(0, 2 * _chunk + 40000));
      await writer.close();
      expect(writer.isComplete, isFalse);
      expect(part.lengthSync(), 32 + 2 * SealedFile.sealedChunkLength, reason: 'the tail was never sealed');

      final from = await SealedFile.resumable(part);
      expect(from, 2 * _chunk);
      final rest = await SealedWriter.append(part, from: from!, total: data.length);
      await rest.add(data.sublist(from));
      await rest.close();

      expect(rest.isComplete, isTrue);
      expect(await readAll(part), data);
    });

    test('a chunk written half-way by a crash is cut off', () async {
      final data = plain(3 * _chunk);
      final part = File('${dir.path}/f.part');
      final writer = await SealedWriter.create(part, total: data.length);
      await writer.add(data.sublist(0, 2 * _chunk));
      await writer.close();
      part.writeAsBytesSync([1, 2, 3, 4, 5], mode: FileMode.append);

      expect(await SealedFile.resumable(part), 2 * _chunk);
      expect(part.lengthSync(), 32 + 2 * SealedFile.sealedChunkLength);
    });

    test('a last whole chunk that does not open is asked for again', () async {
      final data = plain(3 * _chunk);
      final part = File('${dir.path}/f.part');
      final writer = await SealedWriter.create(part, total: data.length);
      await writer.add(data.sublist(0, 2 * _chunk));
      await writer.close();
      final bytes = part.readAsBytesSync()..[32 + SealedFile.sealedChunkLength + 3] ^= 0xFF;
      part.writeAsBytesSync(bytes);

      expect(await SealedFile.resumable(part), _chunk);
    });

    test('a whole file the download did not live to rename gives back its last chunk, and comes out whole again', () async {
      final data = plain(2 * _chunk);
      final part = await seal(data, name: 'f.part');

      final from = await SealedFile.resumable(part);
      expect(from, _chunk, reason: 'its last chunk was sealed as the last');
      final rest = await SealedWriter.append(part, from: from!, total: data.length);
      await rest.add(data.sublist(from));
      await rest.close();
      expect(await readAll(part), data);
    });

    test('a part of no sealed file is nothing to go on from', () async {
      final part = File('${dir.path}/f.part')..writeAsBytesSync(plain(100));
      expect(await SealedFile.resumable(part), isNull);
      final short = File('${dir.path}/g.part')..writeAsBytesSync([1, 2]);
      expect(await SealedFile.resumable(short), isNull);
    });
  });

  group('written out plain', () {
    test('a sealed file comes out as its plain bytes, wherever it is asked to', () async {
      final data = plain(2 * _chunk + 77);
      final sealed = await seal(data);
      final out = File('${dir.path}/out.mp4');

      await SealedFile.writePlain(from: sealed, to: out);

      expect(out.readAsBytesSync(), data);
    });

    test('a plain file is copied as it is', () async {
      final data = plain(300);
      final source = File('${dir.path}/photo.png')..writeAsBytesSync(data);
      final out = File('${dir.path}/out.png');

      await SealedFile.writePlain(from: source, to: out);

      expect(out.readAsBytesSync(), data);
    });

    test('a copy that cannot be made in full leaves nothing behind', () async {
      final sealed = await seal(plain(3 * _chunk));
      final bytes = sealed.readAsBytesSync()..[32 + 2 * SealedFile.sealedChunkLength + 9] ^= 0x10;
      sealed.writeAsBytesSync(bytes);
      final out = File('${dir.path}/out.bin');

      await expectLater(SealedFile.writePlain(from: sealed, to: out), throwsA(isA<VaultException>()));
      expect(out.existsSync(), isFalse, reason: 'two chunks of a plain file were on the disk');
    });
  });

  group('the writer', () {
    test('refuses more bytes than the file was started for, and takes none of them', () async {
      final writer = await SealedWriter.create(File('${dir.path}/f'), total: 10);
      await writer.add(plain(6));

      await expectLater(writer.add(plain(5)), throwsA(isA<SealedFileException>().having((e) => e.error, 'error', SealedFileError.tooLong)));
      expect(writer.written, 6);
      await writer.close();
    });

    test('goes on only from a chunk boundary', () async {
      final part = await seal(plain(2 * _chunk), name: 'f.part');
      await expectLater(SealedWriter.append(part, from: 100, total: 2 * _chunk), throwsArgumentError);
    });
  });
}
