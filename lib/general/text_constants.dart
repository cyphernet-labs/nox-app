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

  // Settings: Notifications (7.2)
  static const String settingsNotificationsTitle = 'Notifications';
  static const String notificationsPushTitle = 'Push notifications';
  static const String notificationsPushSubtitle = 'Get notified about your chats.';
  static const String notificationsDeniedMessage = 'Notifications are turned off in system settings.';
  static const String actionOpenSettings = 'Open settings';

  // Settings: Terms (7.6) — placeholder legal copy until legal text is delivered.
  static const String settingsTermsTitle = 'Terms';
  static const String termsTermsHeading = 'Terms of Service';
  static const String termsTermsBody = 'Placeholder Terms of Service. The final text will be provided before release.';
  static const String termsPrivacyHeading = 'Privacy';
  static const String termsPrivacyBody = 'Placeholder Privacy notice. NOX is end-to-end encrypted; the server never sees message content.';
  static const String versionLabel = 'Version';

  // Settings: About (7.7)
  static const String settingsAboutTitle = 'About';

  // Onboarding: Login / ID entry (2.1)
  static const String loginSignIn = 'Sign in';
  static const String loginIdLabel = 'Your ID';
  static const String loginIdHint = 'Paste or enter your ID';
  static const String actionPaste = 'Paste';
  static const String loginScanQr = 'Scan QR';
  static const String loginInvalidId = 'Invalid identifier';
  static const String loginNetworkError = 'Could not sign in. Check your connection and try again.';
  static const String onboardTitleSignIn = 'NOX · Sign in';

  // Onboarding: QR scan (2.2)
  static const String tooltipFlashlight = 'Flashlight';
  static const String tooltipSwitchCamera = 'Switch camera';
  static const String qrAimHint = 'Aim your camera at a QR code';
  static const String qrEnterManually = 'Enter manually';
  static const String qrPermissionTitle = 'Camera access needed';
  static const String qrPermissionMessage = 'To scan a QR code, allow camera access in system settings.';
  static const String qrInvalidSnackbar = 'This QR code is invalid. Try another one.';
  static const String qrDesktopTitle = 'Scan a QR code';
  static const String qrDesktopHelper = 'Point your webcam at a code, or enter the ID manually.';
  static const String onboardTitleScanQr = 'NOX · Scan QR';

  // Onboarding: Set username (2.3)
  static const String usernameLabel = 'Name';
  static const String usernameHint = 'How others will see you';
  static const String usernameHelper = 'Others see this name. You can change it now or later in Settings.';
  static const String usernameCharsetError = 'Contains invalid characters (allowed: letters, digits, - _ .)';
  static const String nameTakenError = 'This name is taken';
  static const String actionDone = 'Done';
  static const String actionSkip = 'Skip';
  static const String onboardTitleSetUp = 'NOX · Set up';

  // Create chat (6.1)
  static const String createChatTitle = 'New chat';
  static const String createChatNameLabel = 'Chat name';
  static const String createChatNameHint = 'e.g. Random thoughts';
  static const String createChatNetworkError = 'Could not create chat. Check your connection and try again.';
  static const String actionCreate = 'Create';
  static const String actionCancel = 'Cancel';
}
