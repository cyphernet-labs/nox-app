/// Contract §7: the CLIENT derives an attachment's `mime` from the file name
/// extension via a local table — the picker never reads bytes, and the server
/// takes the value it echoes from `file.uploadBegin`. An unknown or absent
/// extension is [fallback]. Kept beside [FileType] because both read the same
/// extension; the category drives the icon, the mime travels on the wire.
abstract final class MimeTypes {
  /// The contract's own default for an extension the table does not know.
  static const String fallback = 'application/octet-stream';

  /// The extension of [name] without the dot, or null when there is none
  /// (a leading dot is a hidden file, not an extension).
  static String? extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return null;
    return name.substring(dot + 1);
  }

  /// The mime a file called [name] is sent with.
  static String forFileName(String name) => forExtension(extensionOf(name));

  /// The mime for a bare extension (no dot, any case).
  static String forExtension(String? ext) {
    switch (ext?.toLowerCase()) {
      // Images
      case 'jpg' || 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'bmp':
        return 'image/bmp';
      case 'svg':
        return 'image/svg+xml';
      // Video
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'mkv':
        return 'video/x-matroska';
      case 'avi':
        return 'video/x-msvideo';
      case 'webm':
        return 'video/webm';
      // Audio
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
        return 'audio/ogg';
      // Documents
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'odt':
        return 'application/vnd.oasis.opendocument.text';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ods':
        return 'application/vnd.oasis.opendocument.spreadsheet';
      case 'csv':
        return 'text/csv';
      case 'txt' || 'log':
        return 'text/plain';
      case 'md':
        return 'text/markdown';
      case 'rtf':
        return 'application/rtf';
      // Archives
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/vnd.rar';
      case '7z':
        return 'application/x-7z-compressed';
      case 'tar':
        return 'application/x-tar';
      case 'gz':
        return 'application/gzip';
      default:
        return fallback;
    }
  }
}
