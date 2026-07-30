/// Semantic opacity (alpha) tokens applied to `ColorScheme` colors — the single
/// source for the handful of magic `withValues(alpha:)` values scattered across the
/// UI. Kept in the theme layer so the presentation widgets carry no raw opacity
/// literals (design-token discipline).
abstract final class NoxOpacity {
  /// Modal scrim drawn over the app behind an overlay — the side-sheet barrier and
  /// the chat-card / file-view standalone previews. (Consolidated from a 0.5/0.55
  /// split to a single 0.5.)
  static const double scrim = 0.5;

  /// Disabled-state foreground (M3 38% on-surface) — inactive icon buttons.
  static const double disabled = 0.38;

  /// The subtle ring every generated avatar carries (`0 0 0 2px onSurface@0.06`).
  static const double ring = 0.06;
}
