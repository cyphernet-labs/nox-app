import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/data/sync/pair_request_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/person/pair_request.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/repository/person/person_repository.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'pair_request_bloc.freezed.dart';
part 'pair_request_event.dart';
part 'pair_request_state.dart';

/// Answers one waiting invite (contract §8B).
///
/// One request, never "let somebody in": two people knocking is two decisions,
/// and an answer that meant "yes to whoever is at the door" would let the
/// second one through on the first one's permission.
class PairRequestBloc extends BaseBloc<PairRequestEvent, PairRequestState> {
  PairRequestBloc({required this.requestId}) : super(const PairRequestState()) {
    on<PairRequestAnswered>(_onAnswered);
    on<PairRequestGone>((_, emit) => emit(state.copyWith(sending: false, settled: true)));
    _watchGone();
  }

  final String requestId;

  StreamSubscription<List<PairRequest>>? _open;

  PersonRepository? get _repository => getIt.isRegistered<PersonRepository>() ? getIt<PersonRepository>() : null;

  /// Closes the surface when the question stops being open — because ANOTHER
  /// device of the owner answered it, or because it ran out of time.
  ///
  /// Without this the second device is a dead end: the modal has no barrier
  /// dismiss, no back arrow and no Escape, and both its buttons now answer a
  /// settled request, which the server refuses. The owner would be left tapping
  /// a failure forever. The contract broadcasts the outcome to every device of
  /// the owner for exactly this reason.
  void _watchGone() {
    if (!getIt.isRegistered<PairRequestService>()) return;
    _open = getIt<PairRequestService>().open.listen((requests) {
      if (isClosed) return;
      if (requests.any((request) => request.requestId == requestId)) return;
      add(const PairRequestEvent.gone());
    });
  }

  @override
  Future<void> close() async {
    await _open?.cancel();
    return super.close();
  }

  /// Marks the question finished with, so closing the surface does not re-open
  /// it. The service's own removal covers the ordinary case; this covers the
  /// ones where no outcome frame ever arrives.
  void _forget() {
    if (!getIt.isRegistered<PairRequestService>()) return;
    getIt<PairRequestService>().forget(requestId);
  }

  Future<void> _onAnswered(PairRequestAnswered event, Emitter<PairRequestState> emit) async {
    if (state.sending || state.settled) return;
    emit(state.copyWith(sending: true, failed: false));
    final repository = _repository;
    if (repository == null) {
      emit(state.copyWith(sending: false, failed: true));
      return;
    }
    final result = await repository.confirm(requestId: requestId, approve: event.approve);
    result.match<void>(
      // Settled, whichever way. The screen closes on this; the server tells
      // every other device of the owner separately, so none of them is left
      // holding a question that has been answered.
      onData: (_) {
        _forget();
        emit(state.copyWith(sending: false, settled: true));
      },
      onError: (e) {
        // Everything the server will keep refusing: somebody answered it, it
        // ran out of time, or it cannot be answered by this person at all.
        // Offering the buttons again would offer the same refusal again. notOwner is not something
        // this person can retry out of; `authentication` is what the wire's
        // `invalid_token` becomes, and person.confirm sends it when the waiting
        // device's key acquired an owner during the wait - nothing is recorded,
        // the request expires on its own, and no answer can ever succeed.
        //
        // Each of these has to leave the LIST as well as the screen: the server
        // sends no outcome for them, and a question still in the list re-opens
        // the moment its surface closes.
        final gone =
            e == RepositoryException.notFound ||
            e == RepositoryException.pairTimeout ||
            e == RepositoryException.notOwner ||
            e == RepositoryException.authentication;
        if (gone) _forget();
        // A dead channel is told apart from anything else: the question is
        // still open on the server, the answer simply did not leave. Without
        // that distinction an offline owner reads "couldn't answer" as a broken
        // app and has no exit to prove otherwise.
        emit(state.copyWith(sending: false, settled: gone, failed: !gone, offline: e == RepositoryException.connection));
      },
    );
  }
}
