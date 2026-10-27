import 'dart:typed_data';

/// The files this device keeps (phase 048), as the screens reach them. What
/// NOX keeps on the disk is sealed, so it is opened on the way: into memory
/// for a picture, into a plain copy for whatever can only read a file, into
/// the place the person chose for Save. A file of the person's own - the one
/// just picked in the composer - is read as it is.
///
/// Takes paths, never `dart:io` types: `domain` imports nothing.
abstract class LocalFilesService {
  /// The plain bytes of the file at [path], in memory (FR-006): a picture to
  /// draw, never a plain copy on the disk.
  Future<Uint8List> read(String path);

  /// A plain copy of the file at [path], named [name], in the app's own
  /// temporary folder (FR-007): for a player, or another app, that can only
  /// read a file. Gone with [releaseCopy] - the player closed - or at the next
  /// launch or logout ([clearCopies]), whichever comes first. A copy that
  /// cannot be made - no room on the disk - throws and leaves nothing.
  Future<String> openCopy({required String path, required String name});

  /// Deletes a copy [openCopy] made.
  Future<void> releaseCopy(String copy);

  /// Writes the plain file to [destination], the place the person chose
  /// (FR-008).
  Future<void> saveTo({required String path, required String destination});

  /// Deletes every copy still there: at every launch, at every logout.
  Future<void> clearCopies();

  /// Lets go of a file the composer picked (048 review): when it is a copy
  /// the platform's picker made in the app's own storage - Android's cache,
  /// iOS's inbox - and no queued message still sends from it, it is deleted;
  /// a file of the person's own is never touched. Called when the draft is
  /// dropped, replaced or refused; the queue lets go of it itself once it
  /// sealed its own copy.
  Future<void> releasePicked(String path);

  /// Deletes every copy the platform's picker left but those in [keep]: a
  /// logout keeps none; a launch keeps what the queue still sends from - a
  /// message whose own copy could not be made, or one queued by an older
  /// build.
  Future<void> clearPicked({Set<String> keep = const <String>{}});
}
