part of 'pair_request_bloc.dart';

@freezed
abstract class PairRequestState with _$PairRequestState {
  const PairRequestState._();

  const factory PairRequestState({
    @Default(false) bool sending,
    @Default(false) bool failed,

    /// The answer reached the server. The surface closes on this rather than on
    /// the tap: closing first would leave the owner believing they decided
    /// something the server never heard.
    @Default(false) bool settled,
  }) = _PairRequestState;
}
