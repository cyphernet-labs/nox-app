import 'package:injectable/injectable.dart';
import 'package:nox_app/data/sync/live_session_starter.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/domain/repository/app/app_state_repository.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/general/onboarding_mock_data.dart';

/// Mutate source-of-truth (session) → re-derive app state. Single logout path;
/// only forced logout passes `sessionExpired`. Sign-in is a stub (backend TBD).
@LazySingleton(as: AuthRepository, env: [Environment.dev, Environment.prod, Environment.test])
class AuthRepositoryImpl with BaseRepositoryHelper implements AuthRepository {
  AuthRepositoryImpl(
    this._sessionRepository,
    this._appStateRepository,
    this._chatRepository,
    this._messageRepository,
    this._syncRepository,
    this._outboxRepository,
  );

  final SessionRepository _sessionRepository;
  final AppStateRepository _appStateRepository;
  final ChatRepository _chatRepository;
  final MessageRepository _messageRepository;
  final SyncRepository _syncRepository;
  final OutboxRepository _outboxRepository;

  @override
  Future<RepositoryResult<bool>> signIn({required String identifier}) {
    // Normalize once: derive the outcome from AND persist the SAME value so the
    // stored identity can't diverge from the id that was matched (e.g. a pasted
    // "registered\n"). This is normalization, not format validation (FR-011).
    final id = identifier.trim();
    final onboardingComplete = OnboardingMockData.registeredIds.contains(id);
    return _deriveAfter(
      () => _sessionRepository.saveIdentifier(identifier: id, onboardingComplete: onboardingComplete),
      // Logout closed the channel; a sign-in in the same process has to open it
      // again, or the device stays disconnected until the app is restarted.
      afterMutate: () async {
        if (getIt.isRegistered<LiveSessionStarter>()) await getIt<LiveSessionStarter>().restart();
        // Logout cancelled the drain's phase subscription. Without re-arming it
        // here, a re-login in the same process would only ever send when the
        // thread asked directly — a message queued offline would sit there
        // through the next reconnect with nobody to notice it.
        if (getIt.isRegistered<OutboxService>()) getIt<OutboxService>().start();
      },
    );
  }

  @override
  Future<RepositoryResult<bool>> completeOnboarding({String? label}) {
    return _deriveAfter(
      () => _sessionRepository.setOnboardingComplete(label: label),
      // Reconnect so the chosen name actually reaches the server. Stage 1 has
      // no `identity.setLabel` (contract §8.1 puts it in stage 2), so the
      // greeting is the ONLY place a label is stated — and by now the socket
      // has already greeted, under the server-assigned `User<random>`. Without
      // this the user picks a name and everyone else keeps seeing the old one
      // until something happens to reconnect the device.
      afterMutate: () async {
        if (getIt.isRegistered<LiveSessionStarter>()) await getIt<LiveSessionStarter>().restart();
      },
    );
  }

  @override
  Future<RepositoryResult<bool>> logout({bool forced = false}) {
    // Gate the re-derive on a successful wipe: a failed clear() (e.g. a secure-storage
    // PlatformException) must NOT report success while the identifier survives —
    // otherwise the user silently stays authorized (Constitution I: logout fully wipes).
    // After the session is cleared, drop the cached chats + messages so a re-login as a
    // different identity starts clean (Constitution I: full local wipe on identity switch).
    return _deriveAfter(
      _sessionRepository.clear,
      sessionExpired: forced,
      afterMutate: () async {
        // Close the live channel BEFORE emptying anything: an event applied
        // mid-wipe would repopulate the stores this is in the middle of
        // clearing, leaving a logged-out device holding someone's messages.
        if (getIt.isRegistered<LiveSessionStarter>()) await getIt<LiveSessionStarter>().stop();
        // The outgoing drain closes with it, and for the same reason: a pass
        // still in flight would persist a message into the store being emptied.
        //
        // stop() disarms it until the next start(), which is a sign-in. If the
        // wipe below throws, no sign-in follows and the drain would stay dead
        // for the life of the process while the app still shows the user signed
        // in — so a failed wipe puts it back.
        if (getIt.isRegistered<OutboxService>()) await getIt<OutboxService>().stop();
        try {
          // The queue goes FIRST of the stores. It holds message texts that were
          // never sent, and a crash later in the wipe would leave them for the
          // next identity — who would then have them sent, under their name, by
          // the drain that re-arms at the next sign-in.
          await _outboxRepository.clean();
          // The cursor goes next: a crash mid-wipe must leave it behind the
          // stores (safe - replay re-applies idempotently), never ahead of an
          // emptied store (a stale high `since` would skip every row below it
          // and the monotonic guard would keep it stuck forever).
          await _syncRepository.clear();
          await _chatRepository.clean();
          await _messageRepository.clean();
        } catch (_) {
          if (getIt.isRegistered<OutboxService>()) getIt<OutboxService>().start();
          rethrow;
        }
      },
    );
  }

  /// The single home of the "mutate the source of truth → re-derive app state"
  /// contract: run [mutate]; on success run [afterMutate] then re-derive via
  /// `fetchAppState`, on failure propagate the mutation error unchanged (no side
  /// effects, no re-derive, no false success).
  Future<RepositoryResult<bool>> _deriveAfter(
    Future<RepositoryResult<bool>> Function() mutate, {
    bool sessionExpired = false,
    Future<void> Function()? afterMutate,
  }) {
    return execute<bool>(() async {
      final mutated = await mutate();
      if (!mutated.hasData) return mutated;
      if (afterMutate != null) await afterMutate();
      await _appStateRepository.fetchAppState(sessionExpired: sessionExpired);
      return const RepositoryResult<bool>.success(data: true);
    });
  }
}
