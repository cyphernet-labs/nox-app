import 'package:nox_app/domain/model/app/session_model.dart';
import 'package:nox_app/domain/model/session/pending_pairing.dart';
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

  /// The local-data key (phase 048): base64 of 32 bytes, kept for this device
  /// only, that the database and the files on the disk are sealed under. Null
  /// when the secure store has none; an error when the store did not answer,
  /// which is never the same thing - a key that is not there costs the data,
  /// a store that is not ready yet costs a wait.
  Future<RepositoryResult<String?>> storageKey();

  /// Stores a new local-data key.
  Future<RepositoryResult<bool>> saveStorageKey({required String key});

  /// Deletes the local-data key (a logout, or a key that opens nothing).
  Future<RepositoryResult<bool>> forgetStorageKey();

  /// Records which server this installation was paired with, from the link:
  /// where the connection starts, and the server's Ed25519 key (base64) every
  /// connection's Eidolon check must prove (phase 044). Without it the app
  /// would pair with one server and talk to another.
  Future<RepositoryResult<bool>> saveServer({required String address, required String serverKey});

  /// The paired server's address, or null when this install is not paired.
  Future<RepositoryResult<String?>> serverAddress();

  /// The paired server's Ed25519 public key, base64, or null when this install
  /// is not paired. Bound to every connection, on both transports: it is the
  /// one thing that tells the person's own machine from anything else that
  /// answers at that address.
  Future<RepositoryResult<String?>> serverKey();

  /// Whether the stored session was paired before phase 044: an identifier
  /// with no server key. Such a session has nothing its connections could be
  /// checked against, and is wiped once, at the first launch (FR-025).
  ///
  /// A storage READ error is an error, never a `true`: a keychain that is
  /// still locked after a reboot must not cost anybody their session.
  Future<RepositoryResult<bool>> predatesServerKey();

  /// Advances the onboarding flag when the server says the person is already
  /// known, and never the other way round. Called from the greeting-adoption
  /// path, so a device sitting on the naming screen leaves it as soon as the
  /// server reports that this person exists - which is what closes the
  /// "named from another device meanwhile" hole.
  Future<RepositoryResult<bool>> advanceOnboardingIfKnown({required bool created});

  /// Records the identity the server declared at greeting time (contract §3):
  /// its author id and the label it considers current. Both are the server's to
  /// decide — the label may have been changed from another device.
  Future<RepositoryResult<bool>> adoptServerIdentity({required String authorId, required String label});

  /// Reactive display-label signal: emits the current cached label on listen, then
  /// every subsequent change (rename → new label, logout/clear → null). Broadcast —
  /// multiple surfaces (shell avatar, future consumers) may listen concurrently.
  Stream<String?> watchLabel();

  /// Forgets who this device is on the server it cached: the author id belongs
  /// to that world. Called when the server's store turns out to be a different
  /// world: an id from the old one would mark strangers' messages as this
  /// user's own.
  Future<RepositoryResult<bool>> forgetAuthorId();

  /// Records that this process created the person and is now naming them.
  ///
  /// Until onboarding finishes, a greeting may not declare it done: every
  /// greeting after the first says `created == false`, so a mere reconnect
  /// would otherwise swap the root route out from under someone mid-name.
  void noteOnboardingStartedHere();

  /// Remembers a pairing that waits for approval on the device that issued
  /// the invite (phase 046), so a restart within its time goes on waiting for
  /// the same request rather than opening a new one (FR-011). The link
  /// carries the token - a credential - so this lives in secure storage.
  Future<RepositoryResult<bool>> savePendingPairing(PendingPairing pairing);

  /// The pairing [savePendingPairing] remembered, or null.
  Future<RepositoryResult<PendingPairing?>> readPendingPairing();

  /// Forgets it: the wait ended, whichever way.
  Future<RepositoryResult<bool>> clearPendingPairing();

  /// Undoes what a failed sign-in wrote, and nothing else. Narrower than
  /// [clear] on purpose: the device id survives, because a sign-in that never
  /// reached the server did not change which install this is.
  Future<RepositoryResult<bool>> discardSignIn();

  /// Drops keys that only builds before this one ever wrote.
  ///
  /// Called ONCE at bootstrap, not from a read. It is a one-time upgrade step,
  /// settled forever on the first launch after an install updates, and riding
  /// it on [readSession] - the app's hottest repository call - made a read
  /// perform a write and put a migration inside the error envelope that decides
  /// whether a signed-in person sees their chats or the Login screen.
  ///
  /// Never fails a boot: the result is reported, not thrown, and a caller is
  /// free to ignore it. A key that outlives one more launch costs nothing.
  Future<RepositoryResult<bool>> sweepLegacyKeys();

  /// Full wipe: secure storage deleteAll + remove prefs keys (logout). The
  /// sweep may take the local-data key with it; the module keeps its copy, so
  /// what is open stays readable until the end of the wipe, which deletes the
  /// key by name ([forgetStorageKey]).
  Future<RepositoryResult<bool>> clear();
}
