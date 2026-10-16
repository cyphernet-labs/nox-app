import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as hook;

void main() {
  // native_toolchain_rust refuses to build a target its rust-toolchain.toml
  // does not list: without these the hook fails on Linux before cargo runs.
  test('the toolchain carries both Linux targets', () {
    final toolchain = File('rust/rust-toolchain.toml').readAsStringSync();
    for (final triple in ['x86_64-unknown-linux-gnu', 'aarch64-unknown-linux-gnu']) {
      expect(toolchain, contains('"$triple"'));
    }
  });

  // The channel to the server (044) is in the library, so Linux builds it like
  // every other target. A Linux build needs a Linux C toolchain for Arti's C
  // dependencies, so this one runs on a Linux host.
  test(
    'Linux: the hook builds the code asset',
    () async {
      await testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.linux,
        targetArchitecture: Architecture.current,
        check: (input, output) {
          expect(output.assets.code, hasLength(1));
          expect(output.assets.code.single.id, 'package:nox_tor/src/nox_tor_bindings.dart');
        },
      );
    },
    testOn: 'linux',
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
