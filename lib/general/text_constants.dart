/// All user-facing strings (English). No literal copy in widgets.
/// Migration-ready for ARB + flutter_localizations (separate i18n feature).
abstract final class TextConstants {
  const TextConstants._();

  static const String appName = 'NOX';

  // App shell destinations (FR-004)
  static const String chats = 'Chats';
  static const String settings = 'Settings';

  // Generic states
  static const String errorGeneralTitle = 'Something went wrong';
  static const String errorFatalMessage = 'An unexpected error occurred. Please try again.';
  static const String errorNetworkMessage = 'Could not connect. Check your connection and try again.';
  static const String actionTryAgain = 'Try again';
  static const String noData = 'Nothing here yet';
  static const String comingSoon = 'Coming soon';

  // UI-kit widget defaults (FR-012)
  static const String searchHint = 'Search';
  static const String composerHint = 'Message';
  static const String actionDismiss = 'Dismiss';
  static const String noConnection = 'No connection';

  // Icon-only action tooltips / semantics (FR-016)
  static const String tooltipAttachFile = 'Attach file';
  static const String tooltipSend = 'Send';
  static const String tooltipCreateChat = 'New chat';
  static const String tooltipRemove = 'Remove';
  static const String tooltipToggleTheme = 'Toggle theme';
  static const String tooltipBack = 'Back';

  // Home launcher + UI-kit gallery
  static const String uiKitTitle = 'NOX UI Kit';
  static const String uiKitSubtitle = 'Browse every component in the design system.';
  static const String actionOpenUiKit = 'Open UI Kit';
  static const String themeLight = 'Light';
  static const String themeDark = 'Dark';

  // Screens gallery (dev launcher for product screens)
  static const String screensGalleryTitle = 'NOX Screens';
  static const String actionOpenScreens = 'Open Screens';

  // Settings: Appearance (7.3)
  static const String settingsAppearanceTitle = 'Appearance';
  static const String themeSystem = 'System';

  // Settings: Language (7.4)
  static const String settingsLanguageTitle = 'Language';
  static const String languageSystem = 'System';
  static const String languageEnglish = 'English';
  static const String languageUkrainian = 'Українська';
}
