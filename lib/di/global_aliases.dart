import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/app/app_state_repository.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';
import 'package:nox_app/domain/repository/log_repository.dart';
import 'package:nox_app/domain/repository/qr/camera_permission_service.dart';

/// Convenience getters over the DI container.
/// Cross-cutting
LogRepository get logRepository => getIt<LogRepository>();

/// Repositories
ItemRepository get itemRepository => getIt<ItemRepository>();

/// App-state spine
AppStateRepository get appStateRepository => getIt<AppStateRepository>();
AuthRepository get authRepository => getIt<AuthRepository>();
SessionRepository get sessionRepository => getIt<SessionRepository>();

/// QR scan (2.2) — permission service resolved by the scanner widget.
CameraPermissionService get cameraPermissionService => getIt<CameraPermissionService>();
