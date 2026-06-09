import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

/// Thin Dio wrapper. Base URL, auth interceptor, HMAC/security headers and the
/// token source are example/TBD (backend & protocol not chosen) — see
/// contracts/build-flavors.md and blueprint 14-networking-and-auth.md.
@lazySingleton
class ApiClient {
  ApiClient()
      : dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );

  final Dio dio;
}
