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
    _installAdapter();
    // Dio's adapter asks for a client ONCE and caches it, so it would keep the
    // one that was thrown away when the pin changed - and every attachment
    // transfer after a re-pairing would fail for no reason anybody could see.
    _pinned.onDiscarded = _installAdapter;
    if (dio.interceptors.whereType<AuthInterceptor>().isEmpty) {
      dio.interceptors.add(AuthInterceptor(_config));
    }
  }

  /// Points Dio at the shared, checked client. A fresh adapter each time,
  /// because that is the only way to clear the one it caches.
  void _installAdapter() {
    dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => _pinned.client);
  }
}
