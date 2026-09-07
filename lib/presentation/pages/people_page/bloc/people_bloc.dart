import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/data/sync/pair_request_service.dart';
import 'package:nox_app/domain/model/person/pair_request.dart';
import 'package:nox_app/domain/model/person/person_model.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/repository/person/person_repository.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'people_bloc.freezed.dart';
part 'people_event.dart';
part 'people_state.dart';

/// 7.4 People — who lives on this server, and the owner's way to invite
/// somebody new.
///
/// Always read from the server, never from a cache, for the reason the device
/// list is: the answer is short, read rarely, and a stale copy would show
/// somebody who has just joined as absent.
class PeopleBloc extends BaseBloc<PeopleEvent, PeopleState> {
  PeopleBloc() : super(const PeopleState()) {
    on<PeopleInitialize>(_onInitialize);
    on<PeopleInviteRequested>(_onInviteRequested);
    on<PeopleInviteDismissed>((_, emit) => emit(state.copyWith(inviteLink: null, inviteFailed: false)));
    on<PeopleQuestionSettled>(_onQuestionSettled);
    _watchQuestions();
  }

  StreamSubscription<List<PairRequest>>? _questions;
  int _openQuestions = 0;

  /// Re-reads the circle when a question is answered somewhere.
  ///
  /// The person who was just let in appears in `person.list` immediately, but
  /// nothing on this screen would ask again: the surface that took the decision
  /// opens OVER this one and pops back to it.
  ///
  /// The link on screen is deliberately LEFT ALONE. A resolved question says
  /// which request was answered, never which invite it spent, and every
  /// `person.invite` mints its own token - so clearing on any outcome discards
  /// an invite the owner minted and has not sent yet. Nothing revokes it and
  /// nothing lists it (Q17), so a wrongly discarded one is gone for good.
  void _watchQuestions() {
    if (!getIt.isRegistered<PairRequestService>()) return;
    final service = getIt<PairRequestService>();
    _openQuestions = service.current.length;
    _questions = service.open.listen((requests) {
      final settled = requests.length < _openQuestions;
      _openQuestions = requests.length;
      if (settled && !isClosed) add(const PeopleEvent.questionSettled());
    });
  }

  @override
  Future<void> close() async {
    await _questions?.cancel();
    return super.close();
  }

  Future<void> _onQuestionSettled(PeopleQuestionSettled event, Emitter<PeopleState> emit) async {
    await _onInitialize(const PeopleInitialize(), emit);
  }

  PersonRepository? get _repository => getIt.isRegistered<PersonRepository>() ? getIt<PersonRepository>() : null;

  Future<void> _onInitialize(PeopleInitialize event, Emitter<PeopleState> emit) async {
    emit(state.copyWith(loading: true, failed: false));
    final repository = _repository;
    if (repository == null) {
      // Mock flavors have no live channel, so there is no circle to show.
      emit(state.copyWith(loading: false, people: const <PersonModel>[]));
      return;
    }
    final result = await repository.getPeople();
    result.match<void>(
      onData: (people) => emit(state.copyWith(loading: false, people: people, failed: false)),
      onError: (_) => emit(state.copyWith(loading: false, failed: true)),
    );
  }

  Future<void> _onInviteRequested(PeopleInviteRequested event, Emitter<PeopleState> emit) async {
    // One at a time, and the button says so. Every call MINTS A TOKEN that
    // admits a new person for 24 hours and cannot be revoked; a round trip can
    // take ten seconds, and three impatient taps would leave two live invites
    // nothing on this screen ever shows again.
    if (state.inviting) return;
    emit(state.copyWith(inviting: true, inviteFailed: false, notOwner: false));
    final repository = _repository;
    if (repository == null) {
      // A silent failure here reads as a dead button: the person taps "Invite"
      // and nothing at all happens.
      emit(state.copyWith(inviting: false, inviteFailed: true));
      return;
    }
    final result = await repository.invitePerson();
    result.match<void>(
      onData: (link) => emit(state.copyWith(inviting: false, inviteLink: link, inviteFailed: false)),
      // "Only the owner may invite" is not "couldn't create an invite": one
      // says the app should not have offered this at all, the other says try
      // again. This screen is the owner's, so seeing it means the ownership
      // answer went stale - and saying so beats inviting a retry that will
      // fail the same way.
      onError: (e) => emit(
        state.copyWith(inviting: false, notOwner: e == RepositoryException.notOwner, inviteFailed: e != RepositoryException.notOwner),
      ),
    );
  }
}
