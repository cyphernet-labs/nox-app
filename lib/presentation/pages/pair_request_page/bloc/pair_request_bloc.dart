import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/configure_dependencies.dart';
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
  }

  final String requestId;

  PersonRepository? get _repository => getIt.isRegistered<PersonRepository>() ? getIt<PersonRepository>() : null;

  Future<void> _onAnswered(PairRequestAnswered event, Emitter<PairRequestState> emit) async {
    if (state.sending) return;
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
      onData: (_) => emit(state.copyWith(sending: false, settled: true)),
      onError: (_) => emit(state.copyWith(sending: false, failed: true)),
    );
  }
}
