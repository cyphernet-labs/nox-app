import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/repository/app_config/app_config_repository_impl.dart';
import 'package:nox_app/domain/model/app_config/server_limits.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('AppConfigRepository handshake limits (025)', () {
    test('serves the contract defaults before any handshake', () {
      final repo = AppConfigRepositoryImpl(const FlutterSecureStorage(), true);
      expect(repo.limits, ServerLimits.contractDefaults);
      expect(repo.limits.maxMessageBytes, 65536);
      expect(repo.limits.maxAttachmentBytes, 104857600);
      expect(repo.limits.maxFrameBytes, 131072);
    });

    test('updateLimits replaces the served values (the 027 transport writer seam)', () {
      final repo = AppConfigRepositoryImpl(const FlutterSecureStorage(), true);
      const live = ServerLimits(maxMessageBytes: 1000, maxAttachmentBytes: 2000, maxFrameBytes: 3000);

      repo.updateLimits(live);

      expect(repo.limits, live);
    });
  });
}
