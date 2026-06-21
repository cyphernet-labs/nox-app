/// Attachment file category — the single source of truth (domain). Drives the
/// type icon + decorative brand color used by the file glyph / chip. NOX shows
/// type-icon chips only (no content preview). The presentation mappers
/// (`noxFileIcon` / `noxFileColor`) live in
/// `presentation/widgets/primitives/file_type.dart` and import this enum.
enum FileType { image, video, audio, pdf, doc, sheet, text, archive, other }
