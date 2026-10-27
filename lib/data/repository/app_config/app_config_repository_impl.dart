import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/model/app_config/app_config.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/model/app_config/server_limits.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

@LazySingleton(as: AppConfigRepository, env: [Environment.dev, Environment.prod, Environment.test])
class AppConfigRepositoryImpl implements AppConfigRepository {
  AppConfigRepositoryImpl(this._secureStorage, @Named('isTestEnvironment') this._isTestEnvironment);

  final FlutterSecureStorage _secureStorage;
  final bool _isTestEnvironment;

  AppConfig? _config;

  /// In-memory handshake limits: contract defaults until a greeting stores the
  /// server's. In-memory is deliberate - a fresh greeting arrives on every
  /// connection, there is nothing durable to persist.
  ServerLimits _limits = ServerLimits.contractDefaults;

  /// Secure-storage key of a request-level auth token. Nothing writes one: the
  /// channel check (contract §1) authenticates every connection, so the token
  /// stays read-only plumbing for the `Authorization` header.
  static const String _kAuthIdToken = 'auth_id_token';

  @override
  Future<void> initialize({required AppFlavorType flavorType}) async {
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
  ServerLimits get limits => _limits;

  @override
  void updateLimits(ServerLimits limits) {
    _limits = limits;
  }

  @override
  bool get isTestEnvironment => _isTestEnvironment;
}
