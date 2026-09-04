import 'package:nox_app/domain/model/app/session_model.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// Cache-only session store. `identifier` lives in secure storage; the
/// `onboardingComplete` flag and cached `label` in shared_preferences.
abstract class SessionRepository {
  /// Reads the session from cache (no network). `data == null` ⇒ no session.
  Future<RepositoryResult<SessionModel?>> readSession();

  /// Persists the identifier (secure storage) + onboarding flag / label (prefs).
  Future<RepositoryResult<bool>> saveIdentifier({required String identifier, required bool onboardingComplete, String? label});

  /// Marks first-login onboarding complete (+ optionally caches the label).
  ///
  /// MONOTONIC: this flag only ever moves forward. Nothing but a logout may
  /// return a person to onboarding. Without that rule the defect this feature
  /// removes survives in one sequence - someone signed in, was shown the
  /// naming screen, closed the app, then named themselves from another device
  /// would be shown the naming screen again and have that name overwritten.
  Future<RepositoryResult<bool>> setOnboardingComplete({String? label});

  /// Persists a new display label (non-secret prefs) and broadcasts it on [watchLabel].
  /// Does NOT touch the secure identifier. Caller guarantees the label already passed
  /// validation (charset / uniqueness / ≤32).
  Future<RepositoryResult<bool>> updateLabel({required String label});

  /// This installation's opaque id, minted once on first use and kept in secure
  /// storage. It names the DEVICE in a greeting (`device_key`), never the
  /// person: a logout wipes it along with everything else, and the person is
  /// recognised by what they hold, not by which install they happen to be on.
  /// This device's key seed, minted on first use. The public half of the pair
  /// is what the server knows as `device_key`; this half never leaves.
  Future<RepositoryResult<String>> deviceSecret();

  /// Records which server this installation was paired with, from the link.
  /// Without it the app would pair with one server and talk to another.
  Future<RepositoryResult<bool>> saveServer({required String address, required String serverKey});

  /// The paired server's address, or null when this install is not paired.
  Future<RepositoryResult<String?>> serverAddress();

  /// Whether this device has renamed since the server last confirmed a name.
  ///
  /// A greeting states a label only when the answer is true. Stating it every
  /// time turns a stale cache into a rename ping-pong: a device that was offline
  /// through a rename would push the old name back over the new one, and the

  /// Raises the flag without changing the name. Used when the world the name
  /// was confirmed in is gone: the server has never heard it, so it has to be

  /// Advances the onboarding flag when the server says the person is already
  /// known, and never the other way round. Called from the greeting-adoption
  /// path, so a device sitting on the naming screen leaves it as soon as the
  /// server reports that this person exists - which is what closes the
  /// "named from another device meanwhile" hole.
  Future<RepositoryResult<bool>> advanceOnboardingIfKnown({required bool created});

  /// Records the identity the server declared at greeting time (contract §3):
  /// its author id, and the label it considers current. Both are the server's
  /// to decide — the label may have been changed from another device.
  Future<RepositoryResult<bool>> adoptServerIdentity({required String authorId, required String label});

  /// Reactive display-label signal: emits the current cached label on listen, then
  /// every subsequent change (rename → new label, logout/clear → null). Broadcast —
  /// multiple surfaces (shell avatar, future consumers) may listen concurrently.
  Stream<String?> watchLabel();

  /// Forgets the author id this device cached. Called when the server's store
  /// turns out to be a different world: an id from the old one would mark
  /// strangers' messages as this user's own.
  Future<RepositoryResult<bool>> forgetAuthorId();

  /// Records that this process created the person and is now naming them.
  ///
  /// Until onboarding finishes, a greeting may not declare it done: every
  /// greeting after the first says `created == false`, so a mere reconnect
  /// would otherwise swap the root route out from under someone mid-name.
  void noteOnboardingStartedHere();

  /// Undoes what a failed sign-in wrote, and nothing else. Narrower than
  /// [clear] on purpose: the device id survives, because a sign-in that never
  /// reached the server did not change which install this is.
  Future<RepositoryResult<bool>> discardSignIn();

  /// Full wipe: secure storage deleteAll + remove prefs keys (logout).
  Future<RepositoryResult<bool>> clear();
}
