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
  const factory ServerIdentity({
    required String id,
    required String label,

    /// Whether THIS answer brought the person into being (contract §3).
    ///
    /// Nullable on purpose: the wire has three states, and the third one is
    /// load-bearing. Absent means "outcome not stated" — an older server, or a
    /// stage-2 frame that does not carry it — and neither default is free.
    /// Assuming false steals the naming step from a newcomer; assuming true
    /// sends a returning person through onboarding and overwrites the name they
    /// were known by, which is the defect this field exists to remove.
    ///
    /// Describes the answer, not the person: it is never persisted, and the
    /// onboarding decision it feeds is monotonic (a later greeting may declare
    /// onboarding done, never undone).
    bool? created,

    /// Whether THIS person owns the server (contract §3, §8A).
    ///
    /// Nullable for the same reason as [created], and the difference matters:
    /// `null` means the server did not state it — an older build, or a frame
    /// that predates the field — and that is NOT the same as "does not own".
    /// Both render no badge, but only one of them is an answer.
    ///
    /// Unlike [created] it describes the PERSON rather than this answer, so it
    /// is the same in every reply about the same human being, and it is worth
    /// persisting: the badge has to survive an offline launch.
    bool? isOwner,
  }) = _ServerIdentity;
}
