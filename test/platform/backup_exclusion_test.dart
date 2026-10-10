import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What the runners declare about backups (phase 048, FR-010): read from the
/// files the platform builds take, because no test runs on Android or iOS.
void main() {
  const androidNs = 'http://schemas.android.com/apk/res/android';

  String attributeOf(String xml, String element, String attribute) {
    final tag = RegExp('<$element\\b[^>]*>', dotAll: true).firstMatch(xml)?.group(0) ?? '';
    return RegExp('android:$attribute="([^"]*)"').firstMatch(tag)?.group(1) ?? '';
  }

  group('Android', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('turns the backup off and points at rules that keep everything on the device', () {
      expect(manifest, contains(androidNs));
      expect(attributeOf(manifest, 'application', 'allowBackup'), 'false');
      expect(attributeOf(manifest, 'application', 'fullBackupContent'), 'false');
      expect(attributeOf(manifest, 'application', 'dataExtractionRules'), '@xml/data_extraction_rules');
    });

    test('the rules exclude every domain from the cloud backup and from the transfer to a new phone', () {
      final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync();
      const domains = [
        'root',
        'file',
        'database',
        'sharedpref',
        'external',
        'device_root',
        'device_file',
        'device_database',
        'device_sharedpref',
      ];
      for (final section in ['cloud-backup', 'device-transfer']) {
        final body = RegExp('<$section>(.*?)</$section>', dotAll: true).firstMatch(rules)?.group(1);
        expect(body, isNotNull, reason: section);
        expect(body, isNot(contains('<include')), reason: section);
        for (final domain in domains) {
          expect(body, contains('<exclude domain="$domain" path="." />'), reason: '$section / $domain');
        }
      }
    });
  });

  group('iOS and macOS', () {
    test('both runners answer the channel the app marks its data folder through', () {
      for (final runner in ['ios/Runner/AppDelegate.swift', 'macos/Runner/AppDelegate.swift']) {
        final swift = File(runner).readAsStringSync();
        expect(swift, contains('FlutterMethodChannel(name: "nox/backup"'), reason: runner);
        expect(swift, contains('isExcludedFromBackup = true'), reason: runner);
      }
      expect(File('macos/Runner/MainFlutterWindow.swift').readAsStringSync(), contains('NoxBackup.register('));
      expect(File('ios/Runner/AppDelegate.swift').readAsStringSync(), contains('NoxBackup.register('));
    });
  });
}
