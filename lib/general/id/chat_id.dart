import 'dart:math';

/// A chat id this device mints (contract §4, phase 041): `c_` and 32
/// lowercase hex digits - 128 random bits. With it a chat exists here the
/// moment it is created, under the id it keeps on the server and on every
/// other device of the person; nothing is renamed once the server has it.
///
/// [random] is for tests only; the default is the platform's secure source.
String mintChatId([Random? random]) {
  final source = random ?? Random.secure();
  final id = StringBuffer('c_');
  for (var i = 0; i < 16; i++) {
    id.write(source.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return id.toString();
}

/// The shape of an id a device mints, as the server checks it.
final RegExp deviceChatIdPattern = RegExp(r'^c_[0-9a-f]{32}$');
