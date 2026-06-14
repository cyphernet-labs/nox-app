import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Canonical NOX icon registry — Material Symbols Rounded via `material_symbols_icons`
/// (design-system.md §8). Centralizes icon-name references so feature code never
/// uses ad-hoc icon literals. The IconButtons/chips/widgets that consume these
/// are out of scope for the design-system feature.
abstract final class NoxIcons {
  const NoxIcons._();

  // Navigation (§8 / 4.1)
  static const IconData chats = Symbols.forum;
  static const IconData settings = Symbols.settings;
  static const IconData add = Symbols.add;

  // Actions (§8)
  static const IconData back = Symbols.arrow_back;
  static const IconData paste = Symbols.content_paste;
  static const IconData scan = Symbols.qr_code_scanner;
  static const IconData attach = Symbols.attach_file;
  static const IconData send = Symbols.send;
  static const IconData flashlightOn = Symbols.flashlight_on;
  static const IconData flashlightOff = Symbols.flashlight_off;
  static const IconData switchCamera = Symbols.cameraswitch;
  static const IconData search = Symbols.search;
  static const IconData show = Symbols.visibility;
  static const IconData hide = Symbols.visibility_off;
  static const IconData copy = Symbols.content_copy;
  static const IconData qr = Symbols.qr_code;
  static const IconData save = Symbols.download;
  static const IconData edit = Symbols.edit;
  static const IconData removeAttachment = Symbols.close;

  // Message status (§8 / §9.2)
  static const IconData statusPending = Symbols.schedule;
  static const IconData statusSent = Symbols.check;
  static const IconData statusError = Symbols.error;

  // Universal error screen (3.1) + generated-avatar fallback glyph (§2.5)
  static const IconData error = Symbols.error;
  static const IconData avatarFallback = Symbols.forum;

  // Empty-state fallback icons (§10) — used until the real illustration SVGs are
  // delivered (external design order). The illustration widgets are out of scope.
  static const IconData emptyChats = Symbols.forum;
  static const IconData emptyMessages = Symbols.chat_bubble;
  static const IconData emptyFiles = Symbols.folder_open;

  // File-type chip icons (overview «Файлы»); default = [fileOther].
  static const IconData fileImage = Symbols.image;
  static const IconData fileVideo = Symbols.videocam;
  static const IconData fileAudio = Symbols.audiotrack;
  static const IconData filePdf = Symbols.picture_as_pdf;
  static const IconData fileDoc = Symbols.description;
  static const IconData fileSheet = Symbols.table_chart;
  static const IconData fileText = Symbols.article;
  static const IconData fileArchive = Symbols.folder_zip;
  static const IconData fileOther = Symbols.insert_drive_file;
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
