import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:logger/logger.dart';
import 'package:nox_app/domain/repository/log_repository.dart';

/// Single logging channel implementation (logger package). No raw print in lib/.
@LazySingleton(as: LogRepository)
class LoggerLogRepository implements LogRepository {
  LoggerLogRepository() : _logger = Logger(printer: SimplePrinter(printTime: true));

  /// Writes to [output] instead of the console - for tests that read what a
  /// log line would have said.
  @visibleForTesting
  LoggerLogRepository.withOutput(LogOutput output) : _logger = Logger(printer: SimplePrinter(printTime: true), output: output);

  final Logger _logger;

  /// A v3 onion host anywhere in a line.
  static final RegExp _onion = RegExp(r'[a-z2-7]{56}\.onion', caseSensitive: false);

  /// What every line goes through on its way out (phase 040, FR-013).
  ///
  /// The onion address lets anyone who has it ask the Tor network whether this
  /// person's server is up, and it travels inside exceptions this code does not
  /// write: `dart:io` puts the request URI into an `HttpException`, and the
  /// repositories log what they catch. Scrubbing here, on the way out, covers
  /// every one of them, including the ones nobody has met yet.
  static String scrub(String line) => line.replaceAll(_onion, '[onion]');

  @override
  void debug({Object? target, required String message}) {
    _logger.d(scrub('${_tag(target)}$message'));
  }

  @override
  void error({Object? target, required Object error, StackTrace? stackTrace}) {
    final text = scrub('$error');
    _logger.e('${_tag(target)}$text', error: text, stackTrace: stackTrace);
  }

  String _tag(Object? target) => target == null ? '' : '[${target.runtimeType}] ';
}
