part of 'pair_request_bloc.dart';

@freezed
sealed class PairRequestEvent with _$PairRequestEvent {
  const factory PairRequestEvent.answered({required bool approve}) = PairRequestAnswered;

  /// The question stopped being open — answered elsewhere, or out of time.
  const factory PairRequestEvent.gone() = PairRequestGone;
}
