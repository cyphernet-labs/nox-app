import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/person/person_model.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/person/person_repository.dart';

/// The circle over the live socket (contract §8B).
///
/// Not cache-first, for the same reason the device list is not: this is a short
/// list read rarely, and a stale copy would show somebody who has already been
/// let in as absent — or, once revoking a person exists, somebody who has left
/// as present.
@LazySingleton(as: PersonRepository, env: [Environment.dev])
class PersonRepositoryImpl with BaseRepositoryHelper implements PersonRepository {
  PersonRepositoryImpl(this._socket, this._session);

  final NoxSocketClient _socket;
  final SessionRepository _session;

  @override
  Future<RepositoryResult<List<PersonModel>>> getPeople() {
    return execute<List<PersonModel>>(() async {
      final reply = await _socket.send('person.list', const <String, dynamic>{});
      if (!reply.ok) throw RepositoryException.fromWireCode(reply.errorCode ?? '');

      // Which row is "me" is known only here: the server answers about the
      // circle, not about who is asking.
      //
      // The stored author id directly, NOT resolveIdentity: its fallback is the
      // login identifier, whose slot has held the pairing TOKEN since 032. A
      // token can never equal a `u_` id, so the comparison would simply always
      // be false - which is the quiet kind of wrong.
      final session = await _session.readSession();
      final ownId = session.hasData ? (session.data?.authorId ?? '') : '';

      final raw = reply.data?['people'];
      final people = <PersonModel>[];
      if (raw is List) {
        for (final entry in raw) {
          if (entry is! Map<String, dynamic>) continue;
          final id = entry['id'] as String? ?? '';
          people.add(
            PersonModel(
              id: id,
              label: entry['label'] as String? ?? '',
              // Type-checked rather than cast, the same way the greeting reads
              // it: a wrong-typed field is worth ignoring, never worth throwing
              // over. Absent reads as "not the owner" here because the server
              // states the flag for every row it sends — unlike a greeting,
              // where silence means "did not say".
              isOwner: entry['owner'] is bool ? entry['owner'] as bool : false,
              isSelf: id.isNotEmpty && id == ownId,
            ),
          );
        }
      }
      return RepositoryResult<List<PersonModel>>.success(data: people);
    });
  }

  @override
  Future<RepositoryResult<String>> invitePerson() {
    return execute<String>(() async {
      final reply = await _socket.send('person.invite', const <String, dynamic>{});
      if (!reply.ok) throw RepositoryException.fromWireCode(reply.errorCode ?? '');
      final link = reply.data?['link'] as String? ?? '';
      if (link.isEmpty) throw RepositoryException.internal;
      return RepositoryResult<String>.success(data: link);
    });
  }

  @override
  Future<RepositoryResult<bool>> confirm({required String requestId, required bool approve}) {
    return execute<bool>(() async {
      final reply = await _socket.confirmPair(requestId: requestId, approve: approve);
      if (!reply.ok) throw RepositoryException.fromWireCode(reply.errorCode ?? '');
      return const RepositoryResult<bool>.success(data: true);
    });
  }
}
