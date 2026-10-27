/// Attachment file category — the single source of truth (domain). Drives the
/// type icon + decorative brand color used by the file glyph / chip. NOX shows
/// type-icon chips only (no content preview). The presentation mappers
/// (`noxFileIcon` / `noxFileColor`) live in
/// `presentation/widgets/primitives/file_type.dart` and import this enum.
enum FileType {
  image,
  video,
  audio,
  pdf,
  doc,
  sheet,
  text,
  archive,
  other;

  /// Maps a file extension (no dot, any case) to a [FileType]. Unknown or absent
  /// extensions fall back to [other] (feature 017 — real picked attachments).
  static FileType fromExtension(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' || 'bmp' || 'svg':
        return image;
      case 'mp4' || 'mov' || 'mkv' || 'avi' || 'webm':
        return video;
      case 'mp3' || 'm4a' || 'wav' || 'aac' || 'flac' || 'ogg':
        return audio;
      case 'pdf':
        return pdf;
      case 'doc' || 'docx' || 'odt' || 'pages':
        return doc;
      case 'xls' || 'xlsx' || 'csv' || 'numbers' || 'ods':
        return sheet;
      case 'txt' || 'md' || 'rtf' || 'log':
        return text;
      case 'zip' || 'rar' || '7z' || 'tar' || 'gz':
        return archive;
      default:
        return other;
    }
  }
}
