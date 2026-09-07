part of 'pair_request_bloc.dart';

@freezed
sealed class PairRequestEvent with _$PairRequestEvent {
  const factory PairRequestEvent.answered({required bool approve}) = PairRequestAnswered;
}
