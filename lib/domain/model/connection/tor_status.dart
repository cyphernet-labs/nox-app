/// Where the Tor client built into the app stands (phase 040).
enum TorState { stopped, bootstrapping, ready, dormant, failed, obsolete }

/// The last thing that went wrong, as a kind. Never text: a message from Tor
/// can name the onion service, and that must not reach a log or a screen.
///
/// No access-key kinds since phase 045: the client holds no onion access keys,
/// and the module no longer reports a refusal of one.
enum TorError {
  none,
  timeout,
  network,
  internal,

  /// The Tor network no longer accepts this client.
  softwareDeprecated,
}

class TorStatus {
  const TorStatus({required this.state, this.bootstrapPercent = 0, this.error = TorError.none});

  static const TorStatus stopped = TorStatus(state: TorState.stopped);

  final TorState state;
  final int bootstrapPercent;
  final TorError error;

  bool get isReady => state == TorState.ready || state == TorState.dormant;
  bool get isObsolete => state == TorState.obsolete;

  @override
  bool operator ==(Object other) =>
      other is TorStatus && other.state == state && other.bootstrapPercent == bootstrapPercent && other.error == error;

  @override
  int get hashCode => Object.hash(state, bootstrapPercent, error);

  @override
  String toString() => 'TorStatus(${state.name}, $bootstrapPercent%, ${error.name})';
}
