part of 'set_username_bloc.dart';

@freezed
sealed class SetUsernameEvent with _$SetUsernameEvent {
  /// The name text changed (immediate charset / empty feedback).
  const factory SetUsernameEvent.nameChanged(String name) = NameChanged;

  /// Debounced uniqueness check for [name].
  const factory SetUsernameEvent.availabilityRequested(String name) = AvailabilityRequested;

  /// `Done` tapped; [outcome] is the (debug) save result.
  const factory SetUsernameEvent.doneRequested({@Default(UsernameOutcome.success) UsernameOutcome outcome}) = DoneRequested;
}
