import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

/// Builds `rust/` into the code asset of `package:nox_tor/src/nox_tor_bindings.dart`.
///
/// Every target gets the asset, Linux included: the channel to the server
/// (044) lives in it, and the app has no other way to its server. The embedded
/// Tor client is in the same library and stays off on Linux until 045.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    await RustBuilder(
      assetName: 'src/nox_tor_bindings.dart',
      extraCargoEnvironmentVariables: {..._androidMinApiToolchain(code), ..._appleDeploymentTargets(code)},
    ).run(input: input, output: output);
    // native_toolchain_rust tracks only the .rs files cargo reports. Without
    // these, a manifest, lockfile or toolchain change leaves a stale library.
    output.dependencies.addAll([
      for (final f in ['Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml']) input.packageRoot.resolve('rust/$f'),
    ]);
  });
}

/// native_toolchain_rust links Android with the API-35 clang driver whatever
/// minSdk is (its issue #113: crashes on load below API 30). Point C, C++ and
/// the linker at the driver for the app's real minimum instead.
Map<String, String> _androidMinApiToolchain(CodeConfig code) {
  if (code.targetOS != OS.android) return const {};
  final api = code.android.targetNdkApi;
  final (rustTriple, ndkTriple) = switch (code.targetArchitecture) {
    Architecture.arm64 => ('aarch64-linux-android', 'aarch64-linux-android'),
    Architecture.arm => ('armv7-linux-androideabi', 'armv7a-linux-androideabi'),
    Architecture.x64 => ('x86_64-linux-android', 'x86_64-linux-android'),
    final other => throw UnsupportedError('Android $other'),
  };
  final binDir = File.fromUri(code.cCompiler!.compiler).parent.path;
  final suffix = Platform.isWindows ? '.cmd' : '';
  final clang = '$binDir${Platform.pathSeparator}$ndkTriple$api-clang$suffix';
  final clangPp = '$binDir${Platform.pathSeparator}$ndkTriple$api-clang++$suffix';
  final envTriple = rustTriple.replaceAll('-', '_');
  return {'CC_$envTriple': clang, 'CXX_$envTriple': clangPp, 'CARGO_TARGET_${envTriple.toUpperCase()}_LINKER': clang};
}

/// Without a deployment target the C dependencies of Arti build for the SDK's
/// newest OS while Rust targets its own default, and linking fails. These are
/// the app's own minimums.
Map<String, String> _appleDeploymentTargets(CodeConfig code) => switch (code.targetOS) {
  OS.iOS => const {'IPHONEOS_DEPLOYMENT_TARGET': '13.0'},
  OS.macOS => const {'MACOSX_DEPLOYMENT_TARGET': '10.15'},
  _ => const {},
};
