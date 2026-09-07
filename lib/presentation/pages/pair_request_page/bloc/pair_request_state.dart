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

    /// The answer could not leave this device. The question is still open on
    /// the server and will still be there when the channel returns — which is
    /// a different sentence to read than "something went wrong".
    @Default(false) bool offline,
  }) = _PairRequestState;
}
