import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/model/app_config/app_config.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

@LazySingleton(as: AppConfigRepository, env: [Environment.dev, Environment.prod, Environment.test])
class AppConfigRepositoryImpl implements AppConfigRepository {
  AppConfigRepositoryImpl(this._secureStorage, @Named('isTestEnvironment') this._isTestEnvironment);

  final FlutterSecureStorage _secureStorage;
  final bool _isTestEnvironment;

  AppConfig? _config;

  /// Secure-storage key for the (future) auth token. No writer yet — a real sign-in
  /// will persist it (TBD); read-only plumbing this phase.
  static const String _kAuthIdToken = 'auth_id_token';

  @override
  Future<void> initialize({required AppFlavorType flavorType}) async {
    // apiUrl is a TBD placeholder (null → no real requests); a per-flavor real URL
    // lands with the backend. Token/security-header bootstrap is example/TBD.
    _config = AppConfig(flavor: flavorType);
  }

  @override
  AppConfig get config => _config ?? (throw StateError('AppConfigRepository.initialize was not called'));

  @override
  Future<String?> getUserAuthIdToken() async {
    // Trim so a blank/whitespace-only stored value reads as absent (null) rather than
    // producing a malformed `Bearer   ` header — matches the sibling signIn() trim.
    final token = (await _secureStorage.read(key: _kAuthIdToken))?.trim();
    return (token == null || token.isEmpty) ? null : token;
  }

  @override
  bool get isTestEnvironment => _isTestEnvironment;
}
