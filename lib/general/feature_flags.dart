/// Compile-time / config-time feature toggles. Keep flags additive and short-lived.
abstract final class FeatureFlags {
  const FeatureFlags._();

  static const bool enableSearch = true;

  static const bool enablePullToRefresh = true;
}
