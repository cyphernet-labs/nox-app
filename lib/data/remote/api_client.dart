import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/interceptor/auth_interceptor.dart';
import 'package:nox_app/data/remote/pinned_http_client.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

/// Thin Dio wrapper carrying the REST half of the transport: the BYTES of
/// attachments, which is all contract v0 ever sends over HTTP. Commands travel
/// the WebSocket envelope (feature 026) and always will.
///
/// Both halves go to one machine over one pinned client, so the file transfer
/// is checked against the server's fingerprint exactly as the socket is. Until
/// this feature it was plain `http` - half of "the channel is protected" was
/// simply not true.
@lazySingleton
class ApiClient {
  ApiClient(this._config, this._pinned)
    : dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 30), receiveTimeout: const Duration(seconds: 30)));

  final AppConfigRepository _config;
  final PinnedHttpClient _pinned;
  final Dio dio;

  /// Points the client at the paired server and installs the interceptor.
  /// Idempotent for the interceptor; the base URL is re-pointed on every call.
  ///
  /// [address] is REQUIRED, and there is no build-time fallback any more. An
  /// address that came from the build has no fingerprint by construction, so a
  /// connection to it could not be checked - which is the one thing this phase
  /// forbids. It is also the wrong machine: an attachment uploaded there would
  /// be referenced from a message on the paired server, where its id means
  /// nothing.
  void initBase({required String address}) {
    if (address.isNotEmpty) {
      dio.options.baseUrl = address.contains('://') ? address : 'https://$address';
    }
    // The same HttpClient the socket uses, handed over on every call because
    // Dio asks for one per request and a fresh client per request would be a
    // fresh TLS session per attachment.
    dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => _pinned.client);
    if (dio.interceptors.whereType<AuthInterceptor>().isEmpty) {
      dio.interceptors.add(AuthInterceptor(_config));
    }
  }
}
