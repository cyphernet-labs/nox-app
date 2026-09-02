@Tags(['golden'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/presentation/pages/file_view_page/file_view_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/golden.dart';

/// The screen owns a BLoC over a real repository since feature 028, so these
/// need a container — and they need the bytes to be present, or every baseline
/// would pin the "these bytes are gone" state rather than the screen people
/// actually see.
void main() {
  late File bytes;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    bytes = File('${Directory.systemTemp.path}/nox_golden_file_view.pdf')..writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
  });

  tearDown(() async {
    if (bytes.existsSync()) bytes.deleteSync();
    await getIt.reset();
  });

  MessageAttachment file() => MessageAttachment(
    id: 'f',
    type: FileType.pdf,
    name: 'design-spec.pdf',
    sizeBytes: 2516582,
    // On this device already: the loaded state, which is what the old fake
    // 1000ms animation used to settle into.
    localPath: bytes.path,
  );

  goldenTest('file_view_page', () => FileViewPage(file: file()));
  goldenTestDesktop('file_view_page', () => FileViewPage(file: file()));
}
