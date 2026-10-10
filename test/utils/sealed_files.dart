import 'dart:io';

import 'package:nox_app/data/local/device_vault.dart';
import 'package:nox_app/data/local/sealed_file.dart';
import 'package:nox_app/di/configure_dependencies.dart';

/// Writes [bytes] to [path] as this device keeps a file since phase 048:
/// sealed, under the local-data key of the test container's vault (opened, or
/// made, on the way). Real file IO: under a widget test, call it inside
/// `tester.runAsync`.
Future<File> writeSealed(String path, List<int> bytes) async {
  await getIt<DeviceVault>().ensureOpen();
  final file = File(path);
  final writer = await SealedWriter.create(file, total: bytes.length);
  await writer.add(bytes);
  await writer.close();
  return file;
}
