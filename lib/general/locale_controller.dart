import 'package:flutter/foundation.dart';
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

  /// Writes the choice under [_prefsKey]; a test swaps it to make a save fail.
  @visibleForTesting
  static Future<bool> Function(String value)? debugWrite;

  /// Applies [value] at once (drives the live re-render through [language]),
  /// then persists it. A choice that could not be saved is undone - the app
  /// goes back to the language it had - and `false` tells the screen to say so;
  /// a language that changes now and silently reverts at the next launch would
  /// be a choice the app only pretended to take.
  Future<bool> set(AppLanguage value) async {
    final previous = language.value;
    language.value = value;
    bool saved;
    try {
      final write = debugWrite;
      saved = write != null ? await write(value.name) : await (await SharedPreferences.getInstance()).setString(_prefsKey, value.name);
    } catch (_) {
      saved = false;
    }
    // Undone only while it is still the choice: a later choice made while this
    // write was failing is not taken back with it.
    if (!saved && language.value == value) language.value = previous;
    return saved;
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
