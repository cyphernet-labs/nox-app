import 'package:flutter/foundation.dart';

/// App-wide clock seam for deterministic relative-time rendering.
///
/// Returns the real wall clock in production; tests and golden snapshots can pin a
/// fixed reference via [freeze] so relative-time output (`DateFormatter.relative` /
/// `daySeparator`) and the mock data sources (`GetChatsApi` / `GetMessagesApi`,
/// which seed timestamps as `now - ago`) stay deterministic day-to-day. Without a
/// pin, [now] is exactly `DateTime.now()`, so the production path is unchanged.
///
/// This is a display / mock-determinism seam only — not a source of truth for
/// business timestamps that must reflect the true instant of an action.
class AppClock {
  AppClock._();

  static DateTime? _fixed;

  /// Current time — the pinned value when frozen, otherwise the real wall clock.
  static DateTime now() => _fixed ?? DateTime.now();

  /// Pin [at] as "now" (tests / goldens). Always pair with [reset] in a tearDown.
  @visibleForTesting
  static void freeze(DateTime at) => _fixed = at;

  /// Clear any pinned time, restoring the real wall clock.
  @visibleForTesting
  static void reset() => _fixed = null;
}
