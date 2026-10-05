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

  /// The byte transfers under way, each holding its own token.
  ///
  /// A transfer can outlive the reason it was started: a logout, a change of
  /// server, a path the socket has just abandoned. [cancelTransfers] ends every
  /// one of them at once - each is resumable, so ending it costs only the bytes
  /// in flight, while letting it run would keep reaching a machine or a path
  /// nobody uses any more. One token per transfer, not one shared: a transfer
  /// whose bytes stopped moving is ended on its own, and nothing outlives the
  /// transfer it belonged to.
  final Set<CancelToken> _transfers = <CancelToken>{};

  /// A token for one byte transfer. Hand it back with [endTransfer] once the
  /// transfer is over, whichever way it ended.
  CancelToken beginTransfer() {
    final token = CancelToken();
    _transfers.add(token);
    return token;
  }

  void endTransfer(CancelToken token) => _transfers.remove(token);

  /// Ends every byte transfer under way. A transfer started after this call is
  /// not touched by it.
  void cancelTransfers() {
    final under = List<CancelToken>.of(_transfers);
    _transfers.clear();
    for (final token in under) {
      token.cancel('transfers cancelled');
    }
  }

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
    final previous = dio.options.baseUrl;
    if (address.isNotEmpty) {
      dio.options.baseUrl = address.contains('://') ? address : 'https://$address';
    }
    // A new address is a new path (phase 043): the greeting just arrived some
    // other way, and the old way is gone or about to be - away from home its
    // packets go nowhere, and only the stall limit would ever notice. Ended
    // now, every transfer on it goes on from where it stopped, by the new path.
    if (previous.isNotEmpty && previous != dio.options.baseUrl) cancelTransfers();
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
