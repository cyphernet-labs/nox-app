import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Canonical NOX icon registry — Material Symbols Rounded via `material_symbols_icons`
/// (design-system.md §8). Centralizes icon-name references so feature code never
/// uses ad-hoc icon literals. The IconButtons/chips/widgets that consume these
/// are out of scope for the design-system feature.
abstract final class NoxIcons {
  const NoxIcons._();

  // Navigation (§8 / 4.1)
  static const IconData chats = Symbols.forum_rounded;
  static const IconData settings = Symbols.settings_rounded;
  static const IconData add = Symbols.add_rounded;

  // Actions (§8)
  static const IconData back = Symbols.arrow_back_rounded;
  static const IconData paste = Symbols.content_paste_rounded;
  static const IconData scan = Symbols.qr_code_scanner_rounded;
  static const IconData attach = Symbols.attach_file_rounded;
  static const IconData send = Symbols.send_rounded;
  static const IconData flashlightOn = Symbols.flashlight_on_rounded;
  static const IconData flashlightOff = Symbols.flashlight_off_rounded;
  static const IconData switchCamera = Symbols.cameraswitch_rounded;
  static const IconData search = Symbols.search_rounded;
  static const IconData show = Symbols.visibility_rounded;
  static const IconData hide = Symbols.visibility_off_rounded;
  static const IconData copy = Symbols.content_copy_rounded;
  static const IconData qr = Symbols.qr_code_rounded;
  static const IconData save = Symbols.download_rounded;
  static const IconData edit = Symbols.edit_rounded;
  static const IconData removeAttachment = Symbols.close_rounded;

  // Message status (§8 / §9.2)
  static const IconData statusPending = Symbols.schedule_rounded;
  static const IconData statusSent = Symbols.check_rounded;
  static const IconData statusError = Symbols.error_rounded;

  // Universal error screen (3.1) + generated-avatar fallback glyph (§2.5)
  static const IconData error = Symbols.error_rounded;
  static const IconData avatarFallback = Symbols.forum_rounded;

  // Empty-state fallback icons (§10) — used until the real illustration SVGs are
  // delivered (external design order). The illustration widgets are out of scope.
  static const IconData emptyChats = Symbols.forum_rounded;
  static const IconData emptyMessages = Symbols.chat_bubble_rounded;
  static const IconData emptyFiles = Symbols.folder_open_rounded;

  // File-type chip icons (overview «Файлы»); default = [fileOther].
  static const IconData fileImage = Symbols.image_rounded;
  static const IconData fileVideo = Symbols.videocam_rounded;
  static const IconData fileAudio = Symbols.audiotrack_rounded;
  static const IconData filePdf = Symbols.picture_as_pdf_rounded;
  static const IconData fileDoc = Symbols.description_rounded;
  static const IconData fileSheet = Symbols.table_chart_rounded;
  static const IconData fileText = Symbols.article_rounded;
  static const IconData fileArchive = Symbols.folder_zip_rounded;
  static const IconData fileOther = Symbols.insert_drive_file_rounded;
}

/// Attachment file category for the type -> icon mapping (design-system.md §8 /
/// overview «Файлы»). File CONTENT is never previewed — only this type icon.
enum NoxFileType { image, video, audio, pdf, document, spreadsheet, text, archive, other }

/// Maps a file category to its chip icon. Unknown -> [NoxIcons.fileOther].
IconData noxFileTypeIcon(NoxFileType type) => switch (type) {
  NoxFileType.image => NoxIcons.fileImage,
  NoxFileType.video => NoxIcons.fileVideo,
  NoxFileType.audio => NoxIcons.fileAudio,
  NoxFileType.pdf => NoxIcons.filePdf,
  NoxFileType.document => NoxIcons.fileDoc,
  NoxFileType.spreadsheet => NoxIcons.fileSheet,
  NoxFileType.text => NoxIcons.fileText,
  NoxFileType.archive => NoxIcons.fileArchive,
  NoxFileType.other => NoxIcons.fileOther,
};

/// Classify a filename by extension into a [NoxFileType] (default: [NoxFileType.other]).
NoxFileType noxFileTypeFromExtension(String filename) {
  final dot = filename.lastIndexOf('.');
  final ext = dot >= 0 ? filename.substring(dot + 1).toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' || 'heic' || 'svg' => NoxFileType.image,
    'mp4' || 'mov' || 'avi' || 'mkv' || 'webm' || 'm4v' => NoxFileType.video,
    'mp3' || 'wav' || 'aac' || 'flac' || 'ogg' || 'm4a' => NoxFileType.audio,
    'pdf' => NoxFileType.pdf,
    'doc' || 'docx' || 'odt' || 'rtf' => NoxFileType.document,
    'xls' || 'xlsx' || 'csv' || 'ods' => NoxFileType.spreadsheet,
    'txt' || 'md' || 'log' => NoxFileType.text,
    'zip' || 'rar' || '7z' || 'tar' || 'gz' => NoxFileType.archive,
    _ => NoxFileType.other,
  };
}
