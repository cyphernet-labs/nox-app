import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/app_language.dart';
import 'package:nox_app/general/locale_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final controller = LocaleController.instance;

  tearDown(() {
    // The controller is a process-wide singleton, so its ValueNotifier state
    // leaks between cases — reset it to the default choice after each test.
    controller.language.value = AppLanguage.system;
  });

  group('load', () {
    test('resolves to AppLanguage.system when no choice has been persisted', () async {
      SharedPreferences.setMockInitialValues({});

      await controller.load();

      expect(controller.language.value, AppLanguage.system);
    });

    test('restores the persisted ukrainian choice', () async {
      SharedPreferences.setMockInitialValues({'ui_language': 'ukrainian'});

      await controller.load();

      expect(controller.language.value, AppLanguage.ukrainian);
    });

    test('falls back to AppLanguage.system when the stored value is unknown', () async {
      SharedPreferences.setMockInitialValues({'ui_language': 'klingon'});

      await controller.load();

      expect(controller.language.value, AppLanguage.system);
    });
  });

  group('set', () {
    test('mutates the language notifier to the chosen value', () async {
      SharedPreferences.setMockInitialValues({});

      await controller.set(AppLanguage.english);

      expect(controller.language.value, AppLanguage.english);
    });

    test('persists the chosen value under the ui_language key', () async {
      SharedPreferences.setMockInitialValues({});

      await controller.set(AppLanguage.english);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ui_language'), 'english');
    });
  });

  group('locale', () {
    test('is null for AppLanguage.system so the app follows the device locale', () {
      controller.language.value = AppLanguage.system;

      expect(controller.locale, isNull);
    });

    test('is Locale(en) for AppLanguage.english', () {
      controller.language.value = AppLanguage.english;

      expect(controller.locale, const Locale('en'));
    });

    test('is Locale(uk) for AppLanguage.ukrainian', () {
      controller.language.value = AppLanguage.ukrainian;

      expect(controller.locale, const Locale('uk'));
    });
  });
}
