part of 'connect_bloc.dart';

/// Where the connection screen stands. The refusals stay apart because each
/// asks something different of the person: an expired link means "ask for a
/// new one", a rejected one means "this one cannot be used", a declined one
/// that the other device said no, and a server out of reach means "fix the
/// address, or turn on Use Tor".
enum ConnectStatus {
  idle,
  connecting,

  /// The link is an invite, and the server holds the request it opened until
  /// the device that issued the invite answers (phase 046). The fields have
  /// done their work: the screen waits, and offers only Cancel.
  waiting,

  /// The server refused the link's token as expired - the same answer the
  /// sign-in screen gave before phase 045 - or the request an invite opened
  /// ran out its time unanswered (phase 046).
  linkExpired,

  /// The server refused the link's token as not usable.
  linkRejected,

  /// The device that issued the invite answered Deny (phase 046).
  declined,

  /// No server reached, or the server failed; [ConnectState.problem] says
  /// why when that is known.
  failed,

  /// The person withdrew the request with Cancel (phase 046): the screen
  /// closes, back to where links are entered.
  cancelled,
}

@freezed
abstract class ConnectState with _$ConnectState {
  const ConnectState._();

  const factory ConnectState({
    /// The field "Server address", as typed.
    @Default('') String serverAddress,

    /// The field "Onion address", as typed: the host, `<56>.onion`.
    @Default('') String onionAddress,

    /// `Use Tor` - off until the person ticks it (FR-011).
    @Default(false) bool useTor,

    /// What the link itself put in the two fields, to tell an edit from it:
    /// the link's values are taken as they are, and only an edit is checked.
    @Default('') String linkServerAddress,
    @Default('') String linkOnionAddress,

    /// The current values fail the format check. Shown once the person has
    /// pressed Connect, and live from then on.
    @Default(false) bool serverAddressInvalid,
    @Default(false) bool onionAddressInvalid,
    @Default(false) bool showFieldErrors,
    @Default(ConnectStatus.idle) ConnectStatus status,

    /// Why the attempt cannot reach the server, as the path selector found it
    /// - kept from the moment it shows during an attempt until the person
    /// changes something.
    ConnectionProblem? problem,

    /// Cancel was pressed while the request waits, and the withdrawal is on
    /// its way (phase 046).
    @Default(false) bool cancelling,
  }) = _ConnectState;

  bool get isConnecting => status == ConnectStatus.connecting;

  bool get isWaiting => status == ConnectStatus.waiting;

  /// A pairing is under way - presented, or waiting for approval: nothing on
  /// the screen may change under it, and there is no way back but Cancel.
  bool get isBusy => isConnecting || isWaiting;

  bool get showServerAddressError => showFieldErrors && serverAddressInvalid;

  bool get showOnionAddressError => showFieldErrors && onionAddressInvalid;
}
