import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/service/file/system_save_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('nox/save');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  /// The runner answering the way [reply] says: a value, or an error.
  void runnerAnswers(Object? reply) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (reply is PlatformException) throw reply;
      return reply;
    });
  }

  tearDown(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('the runner is asked to save the file at the path it is given', () async {
    runnerAnswers(true);

    final saved = await SystemSaveDialog().save(path: '/data/cache/nox_open/c1/report.pdf');

    expect(saved, isTrue);
    expect(calls.single.method, 'save');
    expect(calls.single.arguments, {'path': '/data/cache/nox_open/c1/report.pdf'});
  });

  test('a cancelled dialog is no save', () async {
    runnerAnswers(false);

    expect(await SystemSaveDialog().save(path: '/data/cache/nox_open/c1/report.pdf'), isFalse);
  });

  test('a dialog the runner could not show is an error, never a quiet cancel', () async {
    runnerAnswers(PlatformException(code: 'no_view'));

    await expectLater(SystemSaveDialog().save(path: '/data/cache/nox_open/c1/report.pdf'), throwsA(isA<PlatformException>()));
  });
}
