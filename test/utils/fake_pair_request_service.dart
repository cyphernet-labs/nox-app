import 'dart:async';

import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/device/pair_request.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/service/pair_request_service.dart';
import 'package:rxdart/rxdart.dart';

/// A request service the test drives by hand (phase 046): [ask] puts a
/// request up, [resolve] takes it down the way `device.pairResolved` would,
/// and every answer is recorded. [reply] decides how an answer ends; by
/// default it is taken, and the request goes - as the real service does.
class FakePairRequestService implements PairRequestService {
  final BehaviorSubject<List<PairRequest>> _requests = BehaviorSubject<List<PairRequest>>.seeded(const <PairRequest>[]);
  final StreamController<String> _closed = StreamController<String>.broadcast();

  /// Every answer given, in order.
  final List<({String requestId, bool allow})> answers = <({String requestId, bool allow})>[];

  /// How an answer ends. Null takes it.
  Future<RepositoryResult<bool>> Function(String requestId, bool allow)? reply;

  List<PairRequest> get requests => _requests.value;

  void ask(PairRequest request) => _requests.add([...requests, request]);

  void resolve(String requestId) {
    _requests.add(requests.where((r) => r.requestId != requestId).toList());
    _closed.add(requestId);
  }

  @override
  Stream<List<PairRequest>> watchRequests() => _requests.stream;

  @override
  Stream<String> watchClosed() => _closed.stream;

  @override
  Future<RepositoryResult<bool>> answer({required String requestId, required bool allow}) async {
    answers.add((requestId: requestId, allow: allow));
    final result =
        await (reply?.call(requestId, allow) ?? Future<RepositoryResult<bool>>.value(const RepositoryResult<bool>.success(data: true)));
    if (result.hasData) resolve(requestId);
    return result;
  }

  Future<void> close() async {
    await _requests.close();
    await _closed.close();
  }
}

/// Registers a [FakePairRequestService] and hands it back. Pair with
/// `tearDown(getIt.reset)`.
FakePairRequestService registerFakePairRequests() {
  final fake = FakePairRequestService();
  getIt.allowReassignment = true;
  getIt.registerSingleton<PairRequestService>(fake);
  return fake;
}
