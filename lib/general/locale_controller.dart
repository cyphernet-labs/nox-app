import 'package:flutter/widgets.dart';
import 'package:nox_app/general/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide UI language, persisted locally (shared_preferences — a fully-open,
/// non-sensitive preference). Exposes the choice as a [ValueListenable] so
/// `MaterialApp.locale` re-renders the whole app live when it changes.
///
/// A plain singleton (not DI-registered) so both the root [MaterialApp] and the
/// Language screen (7.4) can reach it without threading it through the tree. When
/// the settings-persistence feature lands it can be promoted behind a settings
/// repository; the [language] listenable contract stays.
class LocaleController {
  LocaleController._();

  static final LocaleController instance = LocaleController._();

  static const String _prefsKey = 'ui_language';

  /// Current UI-language choice; [AppLanguage.system] follows the device locale.
  final ValueNotifier<AppLanguage> language = ValueNotifier<AppLanguage>(AppLanguage.system);

  /// Load the persisted choice once at startup. Safe to call fire-and-forget:
  /// it only nudges [language], which re-renders the app via the root listener.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    language.value = _fromName(prefs.getString(_prefsKey));
  }

  /// Persist and apply [value] (drives the live re-render through [language]).
  Future<void> set(AppLanguage value) async {
    language.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value.name);
  }

  /// The [Locale] to hand `MaterialApp.locale`; `null` lets it follow the system
  /// via `supportedLocales` (English fallback).
  Locale? get locale => switch (language.value) {
    AppLanguage.system => null,
    AppLanguage.english => const Locale('en'),
    AppLanguage.ukrainian => const Locale('uk'),
  };

  static AppLanguage _fromName(String? name) => AppLanguage.values.firstWhere((l) => l.name == name, orElse: () => AppLanguage.system);
}
