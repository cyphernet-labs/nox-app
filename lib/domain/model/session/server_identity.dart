import 'package:freezed_annotation/freezed_annotation.dart';

part 'server_identity.freezed.dart';

/// Who the server says we are, sent in every greeting (contract v0 §3).
///
/// The server is the authority here: [label] may have been changed from another
/// device while this one was offline, so the greeting is also how a rename
/// catches up. The device sends its stored label with the greeting, but this
/// reply overwrites it (FR-020).
@freezed
abstract class ServerIdentity with _$ServerIdentity {
  const factory ServerIdentity({required String id, required String label}) = _ServerIdentity;
}
