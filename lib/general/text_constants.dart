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
  static const String actionTryAgain = 'Try again';
  static const String noData = 'Nothing here yet';
  static const String comingSoon = 'Coming soon';

  // Network / connectivity copy (overview §«Сетевые ошибки — копирайт»).
  // Canonical pattern: "Could not <verb>. Check your connection and try again."
  // (the word is "connection", never "internet").
  static const String errorGeneralMessage = 'Could not complete your request. Check your connection and try again.';
  static const String errorLoadChats = 'Could not load chats. Pull to refresh.'; // 5.1 exception
  static const String noConnection = 'No connection'; // persistent MaterialBanner while offline
}
