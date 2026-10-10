import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:nox_app/data/repository/log_repository_impl.dart';

class _Capture extends LogOutput {
  final List<String> lines = <String>[];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

/// What every log line goes through on its way out: no onion address, and no
/// pairing link - a token that pairs a device with this person's server
/// (phase 040, FR-013; phase 044, FR-022).
void main() {
  const v3 = 'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7';
  const old = 'https://nox.app/p/#AQF_AAABH5CjZmMytIk_2XvPJ-jonqlQtYsZD3SB33P1foxqnrVbFo-VEf6WohQoqA1_na5iVUo';
  final onion = '${'abcdefgh' * 7}.onion';

  test('a pairing link becomes [link], whole, wherever it sits in a line', () {
    expect(LoggerLogRepository.scrub('sign-in: $v3 refused'), 'sign-in: [link] refused');
    expect(LoggerLogRepository.scrub('FormatException: unreadable ($v3)'), 'FormatException: unreadable ([link])');
    expect(LoggerLogRepository.scrub(v3.toUpperCase()), '[link]');
  });

  test('so does a link of the builds before version 3, which a person may still paste', () {
    expect(LoggerLogRepository.scrub('pasted $old'), 'pasted [link]');
  });

  test('an onion address becomes [onion], as before', () {
    expect(LoggerLogRepository.scrub('dial $onion:443'), 'dial [onion]:443');
  });

  test('a line with neither passes through as it was', () {
    const plain = 'channel: direct open after 120 ms';
    expect(LoggerLogRepository.scrub(plain), plain);
  });

  test('both levels scrub, the error and its rendering alike', () {
    final capture = _Capture();
    final log = LoggerLogRepository.withOutput(capture);

    log.debug(message: 'link $v3');
    log.error(error: FormatException('unreadable', v3));

    final all = capture.lines.join('\n');
    expect(all, isNot(contains('A6CapfR6Z1mAL')));
    expect(all, contains('[link]'));
  });
}
