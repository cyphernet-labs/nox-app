import 'package:nox_app/domain/model/person/person_model.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// The people of this circle, and the owner's right to invite another one.
///
/// Server-only, like [DeviceRepository] and for the same reason: a cached list
/// would offer to act on somebody who has already left, and it is short and read
/// rarely enough that asking every time costs nothing worth saving.
abstract interface class PersonRepository {
  /// Everyone on this server. Open to any paired device — names are not a
  /// secret, they ride every message.
  Future<RepositoryResult<List<PersonModel>>> getPeople();

  /// Mints an invite for a NEW person and returns the link to show. Lives 24
  /// hours, and only the owner may ask (contract §8B).
  ///
  /// A refusal arrives as [RepositoryException.notOwner], which the app should
  /// never actually see: the screen that calls this is the owner's alone.
  Future<RepositoryResult<String>> invitePerson();

  /// Answers one waiting request. Any device of the owner may, and one answer
  /// settles it for all of them.
  Future<RepositoryResult<bool>> confirm({required String requestId, required bool approve});
}
