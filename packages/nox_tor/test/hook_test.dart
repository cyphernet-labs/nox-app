import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as hook;

void main() {
  test('Linux: the hook emits no code asset and never calls cargo', () async {
    await testCodeBuildHook(
      mainMethod: hook.main,
      targetOS: OS.linux,
      targetArchitecture: Architecture.x64,
      check: (input, output) => expect(output.assets.code, isEmpty),
    );
  });
}
