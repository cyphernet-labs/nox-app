import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

/// Debounce-and-restart transformer for live "...Changed" events (e.g. the username
/// / chat-name availability checks): it waits [duration] of input quiet, then maps
/// the latest event, cancelling any in-flight handler via `switchMap`. Built on
/// rxdart (a direct dependency) — mirrors the `transformer:` convention used by
/// `ItemListBloc` (`sequential()`).
EventTransformer<E> debounceRestartable<E>([Duration duration = const Duration(milliseconds: 300)]) {
  return (events, mapper) => events.debounceTime(duration).switchMap(mapper);
}
