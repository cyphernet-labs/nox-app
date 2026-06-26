import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/widgets/app_theme_toggle.dart';
import 'package:nox_app/presentation/pages/about_page/about_page.dart';
import 'package:nox_app/presentation/pages/appearance_page/appearance_page.dart';
import 'package:nox_app/presentation/pages/chat_card_page/chat_card_page.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/chat_thread_page.dart';
import 'package:nox_app/presentation/pages/chats_list_page/chats_list_page.dart';
import 'package:nox_app/presentation/pages/create_chat_page/create_chat_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/file_view_page/file_view_page.dart';
import 'package:nox_app/presentation/pages/language_page/language_page.dart';
import 'package:nox_app/presentation/pages/login_page/login_page.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_page.dart';
import 'package:nox_app/presentation/pages/qr_scan_page/qr_scan_page.dart';
import 'package:nox_app/presentation/pages/set_username_page/set_username_page.dart';
import 'package:nox_app/presentation/pages/settings_root_page/settings_root_page.dart';
import 'package:nox_app/presentation/pages/splash_page/splash_page.dart';
import 'package:nox_app/presentation/pages/terms_page/terms_page.dart';
import 'package:nox_app/presentation/widgets/shell/app_splash_hairline_widget.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';

/// Dev launcher listing every product screen from the design spec, grouped by the
/// screen-map sections. Each implemented screen opens standalone (the mobile or
/// desktop layout is chosen by window width); a not-yet-built screen shows a
/// "Coming soon" affordance and is disabled. As a screen lands, set its
/// [_ScreenEntry.route] and the row activates — so this gallery doubles as a
/// visual progress tracker. Pushed from `HomePage`; mirrors the `UiKitPage`
/// in-app pattern (no router; each page exposes its own `route()`).
class ScreensGalleryPage extends StatelessWidget {
  const ScreensGalleryPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const ScreensGalleryPage(),
    settings: const RouteSettings(name: '/screens'),
  );

  /// Cap the content width so the list stays readable in a wide desktop window.
  static const double _maxContentWidth = 640;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(TextConstants.screensGalleryTitle),
        bottom: const AppSplashHairlineWidget(),
        actions: const [AppThemeToggle()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: ListView(
            padding: EdgeInsets.only(bottom: AppSpacingTokens.s24),
            children: [for (final section in _sections) ..._buildSection(context, section)],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSection(BuildContext context, _ScreenSection section) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return [
      Padding(
        padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s24, AppSpacingTokens.s16, AppSpacingTokens.s8),
        child: Text(section.title, style: textTheme.titleSmall?.copyWith(color: colorScheme.primary)),
      ),
      for (final entry in section.entries) _ScreenRow(entry: entry),
    ];
  }
}

/// A single screen row. Tappable when [_ScreenEntry.route] is set, otherwise
/// rendered disabled with a "Coming soon" trailing label.
class _ScreenRow extends StatelessWidget {
  const _ScreenRow({required this.entry});

  final _ScreenEntry entry;

  static const double _badgeWidth = 44;
  static const double _badgeHeight = 30;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final available = entry.route != null;
    final badgeColor = available ? colorScheme.secondaryContainer : colorScheme.surfaceContainerHighest;
    final badgeTextColor = available ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant;
    return ListTile(
      enabled: available,
      onTap: available ? () => Navigator.of(context).push(entry.route!()) : null,
      leading: Container(
        width: _badgeWidth,
        height: _badgeHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(NoxRadius.s)),
        child: Text(entry.id, style: textTheme.labelMedium?.copyWith(color: badgeTextColor)),
      ),
      title: Text(entry.title),
      trailing: available
          ? null
          : Text(TextConstants.comingSoon, style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
    );
  }
}

/// One screen in the gallery. [route] is null until the screen is implemented;
/// set it to the page's `route` tear-off (e.g. `SplashPage.route`) to activate.
/// Kept required (not optional) so the analyzer doesn't flag it unused while the
/// gallery is still all-stubs, and so each row spells out its wired/not-wired state.
class _ScreenEntry {
  const _ScreenEntry({required this.id, required this.title, required this.route});

  final String id;
  final String title;
  final Route<void> Function()? route;
}

/// A screen-map section (mirrors `docs/design/spec/top-level-screens.md`).
class _ScreenSection {
  const _ScreenSection({required this.title, required this.entries});

  final String title;
  final List<_ScreenEntry> entries;
}

/// The full screen map. Section/screen labels are dev-catalog copy (English),
/// inline like `UiKitPage`'s section titles. Activate a row by adding its
/// `route:` tear-off as the screen is built.
const List<_ScreenSection> _sections = [
  _ScreenSection(
    title: 'Launch',
    entries: [_ScreenEntry(id: '1.1', title: 'Splash', route: SplashPage.routeDemo)],
  ),
  _ScreenSection(
    title: 'Onboarding',
    entries: [
      _ScreenEntry(id: '2.1', title: 'Login', route: LoginPage.routeDemo),
      _ScreenEntry(id: '2.2', title: 'QR scan', route: QrScanPage.routeDemo),
      _ScreenEntry(id: '2.3', title: 'Set username', route: SetUsernamePage.routeDemo),
    ],
  ),
  _ScreenSection(
    title: 'Error',
    entries: [_ScreenEntry(id: '3.1', title: 'Error', route: AppErrorPage.routeDemo)],
  ),
  _ScreenSection(
    title: 'Shell',
    entries: [_ScreenEntry(id: '4.1', title: 'Tab bar shell', route: TabBarShell.routeDemo)],
  ),
  _ScreenSection(
    title: 'Chats',
    entries: [
      _ScreenEntry(id: '5.1', title: 'Chats list', route: ChatsListPage.routeDemo),
      _ScreenEntry(id: '5.2', title: 'Chat thread', route: ChatThreadPage.routeDemo),
      _ScreenEntry(id: '5.3', title: 'File view', route: FileViewPage.routeDemo),
      _ScreenEntry(id: '5.4', title: 'Chat card', route: ChatCardPage.routeDemo),
    ],
  ),
  _ScreenSection(
    title: 'Create',
    entries: [_ScreenEntry(id: '6.1', title: 'Create chat', route: CreateChatPage.routeDemo)],
  ),
  _ScreenSection(
    title: 'Settings',
    entries: [
      _ScreenEntry(id: '7.1', title: 'Settings', route: SettingsRootPage.routeDemo),
      _ScreenEntry(id: '7.2', title: 'Notifications', route: NotificationsPage.route),
      _ScreenEntry(id: '7.3', title: 'Appearance', route: AppearancePage.route),
      _ScreenEntry(id: '7.4', title: 'Language', route: LanguagePage.route),
      _ScreenEntry(id: '7.6', title: 'Terms', route: TermsPage.route),
      _ScreenEntry(id: '7.7', title: 'About', route: AboutPage.route),
    ],
  ),
];
