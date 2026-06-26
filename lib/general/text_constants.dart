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
  static const String themeSystemCaption = 'Match your device';
  static const String themeLightCaption = 'Always light';
  static const String themeDarkCaption = 'Always dark';

  // Settings: Language (7.4)
  static const String settingsLanguageTitle = 'Language';
  static const String languageSystem = 'System';
  static const String languageEnglish = 'English';
  static const String languageUkrainian = 'Українська';

  // Settings: Notifications (7.2)
  static const String settingsNotificationsTitle = 'Notifications';
  static const String notificationsPushTitle = 'Enable notifications';
  static const String notificationsPushSubtitle = "Only for chats you're in";
  static const String notificationsDeniedTitle = 'Notifications are blocked';
  static const String notificationsDeniedMessage = 'Allow notifications in system settings to receive messages from your chats.';
  static const String actionOpenSettings = 'Open settings';

  // Settings: Terms (7.6) — locked doc heading + section headings; bodies are
  // placeholder until the final legal text is delivered. TODO(legal): real copy.
  static const String settingsTermsTitle = 'Terms';
  static const String termsDocHeading = 'Terms of Service';
  static const String termsAcceptanceHeading = 'Acceptance';
  static const String termsAcceptanceBody = 'By using NOX you accept these terms. If you do not agree, do not use the app.';
  static const String termsIdentityHeading = 'Your identity';
  static const String termsIdentityBody =
      'Your account is an anonymous identifier and a display name — no phone number or email. Keep your identifier safe; anyone who has it can sign in as you.';
  static const String termsContentHeading = 'Content';
  static const String termsContentBody =
      'Chats are an open shared space visible to everyone. You are responsible for what you send; do not post unlawful content.';
  static const String termsPrivacyHeading = 'Privacy';
  static const String termsPrivacyBody = 'NOX is end-to-end encrypted; the server never sees your message content.';
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
  static const String sessionExpiredMessage = 'Your session expired';

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

  // Settings root (7.1) — identity card + logout (reuse: settings, loginIdLabel='Your ID',
  // actionCancel='Cancel', usernameLabel='Name', usernameCharsetError, nameTakenError, settings*Title)
  static const String settingsAccountTitle = 'Account'; // desktop list-detail menu item
  static const String settingsNameEditTooltip = 'Edit';
  static const String idMask = '••••••••'; // 8 dots, fixed length
  static const String idShowTooltip = 'Show';
  static const String idHideTooltip = 'Hide';
  static const String idCopyTooltip = 'Copy';
  static const String idShowQrTooltip = 'Show QR';
  static const String qrSheetTitle = 'Your ID QR';
  static const String qrAccountCaption = 'Show this code to let someone add you';
  static const String actionClose = 'Close';
  static const String copiedToClipboard = 'Copied to clipboard';
  static const String logoutRow = 'Log out';
  static const String logoutDialogTitle = 'Log out?';
  static const String logoutDialogMessage = 'Your ID and local data will be removed from this device.';

  // Chats list (5.1) (reuse: appName='NOX', searchHint='Search', noConnection='No connection')
  static const String chatsEmptyTitle = 'No chats yet';
  static const String chatsEmptyMessage = 'Tap + to create the first one.';
  static const String chatsSearchEmpty = 'No chats found';
  static const String chatsLoadError = 'Could not load chats. Pull to refresh.';
  static const String chatsNoSelectionTitle = 'Select a chat';
  static const String chatsNoSelectionMessage = 'Choose a conversation on the left, or press + to start a new one.';
  static const String chatThreadPlaceholder = 'Chat thread (5.2)'; // dev placeholder destination (M4)

  // Relative time ladder (5.1; reused 5.3/5.4 in M4) — see overview.md
  static const String timeNow = 'now';
  static const String timeYesterday = 'Yesterday';
  static const String timeMinuteSuffix = 'min'; // "5 min"
  static const String timeHourSuffix = 'h'; // "2 h"

  // Chat thread (5.2) (reuse: composerHint='Message', tooltipSend='Send',
  // tooltipAttachFile='Attach file', tooltipRemove='Remove', tooltipBack='Back',
  // noConnection='No connection')
  static const String tooltipRetry = 'Tap to retry';
  static const String tooltipChatInfo = 'Chat info';
  static const String threadEmptyTitle = 'No messages yet';
  static const String threadEmptyMessage = 'Send the first one.';
  static const String dateToday = 'Today';
  static const String dateYesterday = 'Yesterday';
  static String systemChatCreated(String username) => 'Chat created by $username';

  // File view (5.3)
  static const String tooltipSave = 'Save';
  static const String savedToDownloads = 'Saved to Downloads';
  static const String fileDownloadError = 'Could not download file. Check your connection and try again.';
  static const String actionDownload = 'Download';
  static String downloadingProgress(int percent) => 'Downloading… $percent%';

  // Chat card (5.4)
  static const String filesSectionTitle = 'Files';
  static const String filesViewList = 'List';
  static const String filesViewGrid = 'Grid';
  static const String filesEmptyTitle = 'No files yet';
  static const String filesEmptyMessage = 'Files sent in this chat will appear here.';
  static const String chatInfoTitle = 'Details';
  static const String chatInfoLoadError = 'Could not load chat info. Check your connection and try again.';
}
