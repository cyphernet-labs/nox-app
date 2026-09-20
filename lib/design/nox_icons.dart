import 'package:nox_app/design/gen/assets.gen.dart';

/// Semantic icon registry — the named entry point for every NOX icon.
///
/// Each getter forwards to a flutter_gen [SvgGenImage] accessor (`Assets.svg.icons.*`);
/// it carries semantics and the FILL axis from `nox-assets/icons/icons.json` without
/// duplicating any raw asset-path string. All glyphs are stock Material Symbols Rounded
/// (weight 400, optical size 24, grade 0); outlined vs filled is the FILL axis
/// (`name.svg` / `name-fill.svg`), not a separate `*_outlined` ligature.
///
/// Recolor at the call site (icons ship `fill="currentColor"`, no baked color), e.g.
/// `NoxIcons.forum.svg(colorFilter: ColorFilter.mode(color, BlendMode.srcIn))`.
///
/// Covers the 35 referenced glyphs from `icons.json`. The 2 bundled-but-unreferenced
/// outlined variants (`flashlight_on.svg`, `send.svg` — their only used form is filled)
/// are intentionally omitted here; reach them via `Assets.svg.icons.flashlightOn` / `.send`.
abstract final class NoxIcons {
  const NoxIcons._();

  // --- navigation — bottom bar / nav rail (4.1); selected = filled, unselected = outlined ---

  /// Chats tab — unselected (outlined, FILL 0).
  static SvgGenImage get forum => Assets.svg.icons.forum;

  /// Chats tab — selected (filled, FILL 1).
  static SvgGenImage get forumFill => Assets.svg.icons.forumFill;

  /// Settings tab — unselected (outlined, FILL 0).
  static SvgGenImage get settings => Assets.svg.icons.settings;

  /// Settings tab — selected (filled, FILL 1).
  static SvgGenImage get settingsFill => Assets.svg.icons.settingsFill;

  /// Center docked FAB — create chat.
  static SvgGenImage get add => Assets.svg.icons.add;

  // --- actions — AppBar / inline actions ---

  /// Back.
  static SvgGenImage get arrowBack => Assets.svg.icons.arrowBack;

  /// Paste ID.
  static SvgGenImage get contentPaste => Assets.svg.icons.contentPaste;

  /// Open QR scanner.
  static SvgGenImage get qrCodeScanner => Assets.svg.icons.qrCodeScanner;

  /// Attach file.
  static SvgGenImage get attachFile => Assets.svg.icons.attachFile;

  /// Send message (filled, FILL 1).
  static SvgGenImage get sendFill => Assets.svg.icons.sendFill;

  /// Torch on (filled, FILL 1).
  static SvgGenImage get flashlightOnFill => Assets.svg.icons.flashlightOnFill;

  /// Torch off (outlined, FILL 0).
  static SvgGenImage get flashlightOff => Assets.svg.icons.flashlightOff;

  /// Switch camera.
  static SvgGenImage get cameraswitch => Assets.svg.icons.cameraswitch;

  /// Camera permission denied (2.2).
  static SvgGenImage get noPhotography => Assets.svg.icons.noPhotography;

  /// Search chats.
  static SvgGenImage get search => Assets.svg.icons.search;

  /// Reveal ID.
  static SvgGenImage get visibility => Assets.svg.icons.visibility;

  /// Hide ID.
  static SvgGenImage get visibilityOff => Assets.svg.icons.visibilityOff;

  /// Copy ID.
  static SvgGenImage get contentCopy => Assets.svg.icons.contentCopy;

  /// Show QR.
  static SvgGenImage get qrCode => Assets.svg.icons.qrCode;

  /// Save / download file.
  static SvgGenImage get download => Assets.svg.icons.download;

  /// Edit username.
  static SvgGenImage get edit => Assets.svg.icons.edit;

  /// Remove attachment / close.
  static SvgGenImage get close => Assets.svg.icons.close;

  // --- status — own-message delivery status (5.2) ---

  /// Pending — `onSurfaceVariant`.
  static SvgGenImage get schedule => Assets.svg.icons.schedule;

  /// Sent — `onSurfaceVariant`.
  static SvgGenImage get check => Assets.svg.icons.check;

  /// Error — error color (tap to retry); also the universal error glyph (3.1).
  static SvgGenImage get error => Assets.svg.icons.error;

  // --- settings destinations (7.1) — the leading chip of each menu row.
  // Selected rows in the desktop pane draw the FILLED variant, exactly as the
  // bottom bar does for its tabs; unselected rows draw the outlined one.

  /// 7.1 `Account` — unselected.
  static SvgGenImage get person => Assets.svg.icons.person;

  /// 7.1 `Account` — selected.
  static SvgGenImage get personFill => Assets.svg.icons.personFill;

  /// 7.1 `Devices` — unselected.
  static SvgGenImage get devices => Assets.svg.icons.devices;

  /// 7.1 `Devices` — selected.
  static SvgGenImage get devicesFill => Assets.svg.icons.devicesFill;

  /// 7.1 `Notifications` — selected (the outlined bell is [notifications]).
  static SvgGenImage get notificationsFill => Assets.svg.icons.notificationsFill;

  /// 7.1 `Appearance` — unselected.
  static SvgGenImage get palette => Assets.svg.icons.palette;

  /// 7.1 `Appearance` — selected.
  static SvgGenImage get paletteFill => Assets.svg.icons.paletteFill;

  /// 7.1 `Language` — unselected (a globe, not a flag: the option is a language).
  static SvgGenImage get language => Assets.svg.icons.language;

  /// 7.1 `Language` — selected.
  static SvgGenImage get languageFill => Assets.svg.icons.languageFill;

  /// 7.1 `Terms` — selected (the outlined sheet is [description]).
  static SvgGenImage get descriptionFill => Assets.svg.icons.descriptionFill;

  /// 7.1 `About` — unselected.
  static SvgGenImage get info => Assets.svg.icons.info;

  /// 7.1 `About` — selected.
  static SvgGenImage get infoFill => Assets.svg.icons.infoFill;

  /// 7.1 `Log out`. Filled at every width: the design draws the destructive row
  /// filled whether or not it is selected, and it never is.
  static SvgGenImage get logoutFill => Assets.svg.icons.logoutFill;

  // --- notifications / connectivity / disclosure ---

  /// 7.2 notifications switch leading chip (bell).
  static SvgGenImage get notifications => Assets.svg.icons.notifications;

  /// 7.2 notifications denied banner — permission off (bell, struck through).
  static SvgGenImage get notificationsOff => Assets.svg.icons.notificationsOff;

  /// Offline notice — no connection (5.1 / 5.2 offline banner).
  static SvgGenImage get wifiOff => Assets.svg.icons.wifiOff;

  /// Row disclosure chevron — list-row trailing affordance (5.4).
  static SvgGenImage get chevronRight => Assets.svg.icons.chevronRight;

  /// 7.4 Language "System" row leading glyph (device locale).
  static SvgGenImage get smartphone => Assets.svg.icons.smartphone;

  // --- fileTypes — attachment-chip type icons (no content preview); `onSurfaceVariant` ---

  /// Image.
  static SvgGenImage get image => Assets.svg.icons.image;

  /// Video.
  static SvgGenImage get videocam => Assets.svg.icons.videocam;

  /// Audio (`audiotrack` substitute — stock Flutter still `Icons.music_note`).
  static SvgGenImage get musicNote => Assets.svg.icons.musicNote;

  /// PDF.
  static SvgGenImage get pictureAsPdf => Assets.svg.icons.pictureAsPdf;

  /// Document (doc/docx/odt).
  static SvgGenImage get description => Assets.svg.icons.description;

  /// Spreadsheet (xls/csv).
  static SvgGenImage get tableChart => Assets.svg.icons.tableChart;

  /// Text.
  static SvgGenImage get article => Assets.svg.icons.article;

  /// Archive (zip/rar/7z).
  static SvgGenImage get folderZip => Assets.svg.icons.folderZip;

  /// Other / unknown (`insert_drive_file` substitute — stock Flutter still `Icons.insert_drive_file`).
  static SvgGenImage get draft => Assets.svg.icons.draft;

  // --- emptyStates — fallback glyphs until the 3 illustrations ship (see Assets.svg.illustrations) ---

  /// 5.2 no messages.
  static SvgGenImage get chatBubble => Assets.svg.icons.chatBubble;

  /// 5.4 no files.
  static SvgGenImage get folderOpen => Assets.svg.icons.folderOpen;

  /// Start playback of a video attachment (5.3).
  static SvgGenImage get playArrowFill => Assets.svg.icons.playArrowFill;

  /// Pause playback of a video attachment (5.3).
  static SvgGenImage get pauseFill => Assets.svg.icons.pauseFill;
}
