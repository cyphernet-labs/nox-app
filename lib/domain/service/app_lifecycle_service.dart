/// Whether the app is in front of the person (phase 040).
enum AppVisibility { foreground, background }

/// The app's visibility, without Flutter's lifecycle type leaking into the
/// domain.
abstract class AppLifecycleService {
  AppVisibility get visibility;

  /// Every change, from the moment of listening.
  Stream<AppVisibility> watchVisibility();
}
