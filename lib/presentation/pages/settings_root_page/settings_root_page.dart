import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/helpers/app_feedback_helper.dart';
import 'package:nox_app/presentation/pages/about_page/about_body.dart';
import 'package:nox_app/presentation/pages/about_page/about_page.dart';
import 'package:nox_app/presentation/pages/appearance_page/appearance_body.dart';
import 'package:nox_app/presentation/pages/appearance_page/appearance_page.dart';
import 'package:nox_app/presentation/pages/base/base_state_page.dart';
// import 'package:nox_app/presentation/pages/error_page/error_page.dart';
// import 'package:nox_app/presentation/pages/error_page/error_page_params.dart';
import 'package:nox_app/presentation/pages/language_page/language_body.dart';
import 'package:nox_app/presentation/pages/language_page/language_page.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_body.dart';
import 'package:nox_app/presentation/pages/devices_page/devices_body.dart';
import 'package:nox_app/presentation/pages/devices_page/devices_page.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_page.dart';
// import 'package:nox_app/presentation/pages/screens_gallery_page/screens_gallery_page.dart';
// import 'package:nox_app/presentation/pages/ui_kit_page/ui_kit_page.dart';
import 'package:nox_app/presentation/pages/settings_root_page/bloc/settings_root_bloc.dart';
import 'package:nox_app/presentation/pages/splash_page/splash_page.dart';
import 'package:nox_app/presentation/pages/terms_page/terms_body.dart';
import 'package:nox_app/presentation/pages/terms_page/terms_page.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_labeled_field_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_identity_card_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_logout_dialog_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_nav_row_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_list_detail_widget.dart';

/// Desktop settings sections (the list-detail menu items).
enum _Section { account, devices, notifications, appearance, language, terms, about }

/// 7.1 Settings root — the Settings tab body. Mobile: a flat list (identity card +
/// nav rows + Log out). Desktop: a list-detail (menu pane 340 + detail pane ≤680,
/// selection swaps the pane without push; the raw ID is never revealed, an inline
/// account QR is shown instead). Settings rows open the real 7.2–7.7 subscreens;
/// Log out → real 1.1 Splash. Owns [SettingsRootBloc]. `[inShell]` suppresses the
/// back affordance when hosted as a shell tab.
class SettingsRootPage extends StatefulWidget {
  const SettingsRootPage({super.key, this.demo = false, this.inShell = false, this.forceWide, this.jumpToAccount});

  final bool demo;
  final bool inShell;

  /// When hosted in the shell, the shell's layout decision (rail vs bottom bar) is
  /// passed down so the body follows it instead of re-measuring its rail-narrowed
  /// width. Null (standalone) → self-measure against the breakpoint.
  final bool? forceWide;

  /// Bumped by the shell when the desktop rail account avatar is tapped → land on
  /// the Account section. Desktop-only by effect (the avatar lives only in the
  /// rail); on mobile the flat list has no section selection, so it is a no-op.
  final ValueListenable<int>? jumpToAccount;

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const SettingsRootPage(),
    settings: const RouteSettings(name: '/settings'),
  );

  /// Gallery entry: opens standalone with the dev control.
  static Route<void> routeDemo() => MaterialPageRoute<void>(
    builder: (_) => const SettingsRootPage(demo: true),
    settings: const RouteSettings(name: '/settings'),
  );

  @override
  State<SettingsRootPage> createState() => _SettingsRootPageState();
}

class _SettingsRootPageState extends BaseStatePage<SettingsRootPage> {
  late final SettingsRootBloc _bloc;
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  _Section _selected = _Section.account;

  @override
  void initState() {
    super.initState();
    _bloc = SettingsRootBloc()..add(const SettingsRootEvent.initialize());
    _nameFocusNode.addListener(_onNameFocusChange);
    widget.jumpToAccount?.addListener(_onJumpToAccount);
  }

  // Shell account avatar (desktop rail) tapped → land on the Account section.
  // No-op on mobile (the flat list has no section selection).
  void _onJumpToAccount() {
    if (!mounted || _selected == _Section.account) return;
    setState(() => _selected = _Section.account);
  }

  @override
  void dispose() {
    widget.jumpToAccount?.removeListener(_onJumpToAccount);
    _nameFocusNode.removeListener(_onNameFocusChange);
    _nameFocusNode.dispose();
    _nameController.dispose();
    _bloc.close();
    super.dispose();
  }

  // Blur exits the inline name-edit: commit when valid, otherwise revert (so an
  // invalid/taken draft is never a one-way trap and a section switch that unmounts
  // the field can't leave it stuck mid-edit). Mirrors the spec's Enter/Done/blur.
  void _onNameFocusChange() {
    if (!mounted || _nameFocusNode.hasFocus || !_bloc.state.editing) return;
    _bloc.add(_bloc.state.canSave ? const SettingsRootEvent.nameSubmitted() : const SettingsRootEvent.nameEditCancelled());
  }

  void _startEdit() {
    _nameController.text = _bloc.state.name;
    _bloc.add(const SettingsRootEvent.nameEditStarted());
  }

  void _copyId() {
    final id = _bloc.state.rawId;
    // Nothing to copy is not a successful copy. The id is absent until the
    // server has stated one, and confirming an empty clipboard write leaves
    // somebody pasting nothing and wondering where it went.
    if (id.isEmpty) return;
    // Fire-and-forget the clipboard write; the confirmation is instant.
    unawaited(Clipboard.setData(ClipboardData(text: id)));
    showAppSnackBar(context, text: context.l10n.copiedToClipboard);
  }

  Future<void> _logout() async {
    final confirmed = await AppLogoutDialogWidget.show(context);
    if (confirmed != true || !mounted) return;
    if (widget.demo) {
      // Gallery preview: hop to the standalone (demo) Splash without touching real state.
      Navigator.of(context).push(SplashPage.routeDemo());
    } else {
      // Real flow: full wipe + re-derive app state; the spine returns to Login. A
      // failed wipe must NOT present as a successful logout (Constitution I: logout
      // fully wipes) — surface it instead of silently leaving the identity on disk.
      final result = await authRepository.logout();
      if (!mounted) return;
      result.match(
        onData: (_) {},
        onError: (_) => showAppSnackBar(context, text: context.l10n.logoutError, error: true),
      );
    }
  }

  void _openSection(Route<void> route) => Navigator.of(context).push(route);

  // The AppBar / pane-header back affordance. Only used on the standalone (non-shell)
  // routes; the callers gate on `!inShell`, so this always returns a real button.
  Widget _backButton() => IconButton(
    tooltip: context.l10n.tooltipBack,
    icon: AppIconWidget(NoxIcons.arrowBack),
    onPressed: () => Navigator.of(context).maybePop(),
  );

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SettingsRootBloc>.value(
      value: _bloc,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = widget.forceWide ?? (constraints.maxWidth >= Constants.railBreakpoint);
          return BlocBuilder<SettingsRootBloc, SettingsRootState>(
            builder: (context, state) => wide ? _wide(context, state) : _narrow(context, state),
          );
        },
      ),
    );
  }

  // ---- Mobile: flat list ----------------------------------------------------

  Widget _narrow(BuildContext context, SettingsRootState state) {
    return Scaffold(
      appBar: AppBar(leading: widget.inShell ? null : _backButton(), title: Text(context.l10n.settings)),
      body: ListView(
        // Room under the last tile for the docked `+`. The shell's Scaffold insets
        // this body by the bottom BAR, but the FAB is centre-docked and stands
        // ~28 proud of it, so `Log out` - the last thing on the list, and the one
        // you least want mis-tapped - sat under it.
        padding: EdgeInsets.only(bottom: _dockedFabClearance),
        children: [
          Padding(padding: _cardMargin, child: _identityCard(state, wide: false)),
          // One tile per destination, each its own rounded surface with the
          // leading chip the design gives it. Merged into a single card with
          // hairlines between them they read as one lump; bare on the scaffold
          // background they read as an unfinished list.
          AppSettingsNavRowWidget(
            title: context.l10n.settingsDevicesTitle,
            icon: NoxIcons.devices,
            onTap: () => _openSection(DevicesPage.route()),
          ),
          AppSettingsNavRowWidget(
            title: context.l10n.settingsNotificationsTitle,
            icon: NoxIcons.notifications,
            onTap: () => _openSection(NotificationsPage.route()),
          ),
          AppSettingsNavRowWidget(
            title: context.l10n.settingsAppearanceTitle,
            icon: NoxIcons.palette,
            onTap: () => _openSection(AppearancePage.route()),
          ),
          AppSettingsNavRowWidget(
            title: context.l10n.settingsLanguageTitle,
            icon: NoxIcons.language,
            onTap: () => _openSection(LanguagePage.route()),
          ),
          AppSettingsNavRowWidget(
            title: context.l10n.settingsTermsTitle,
            icon: NoxIcons.description,
            onTap: () => _openSection(TermsPage.route()),
          ),
          AppSettingsNavRowWidget(
            title: context.l10n.settingsAboutTitle,
            icon: NoxIcons.info,
            onTap: () => _openSection(AboutPage.route()),
          ),
          SizedBox(height: AppSpacingTokens.s16),
          AppSettingsNavRowWidget(title: context.l10n.logoutRow, icon: NoxIcons.logoutFill, danger: true, onTap: _logout),
          // ..._devMenuRows(),
        ],
      ),
    );
  }

  // The development rows - the screens gallery, the UI-kit gallery, a forced logout
  // and the gallery preview’s fatal-state control - are WITHDRAWN from the product on
  // EVERY flavour. `kDebugMode` kept them out of a release build but left them in
  // every debug run, which is the build a person is actually handed while the app is
  // being finished. The screens they opened still exist and still have their tests;
  // bringing the rows back is uncommenting this block and its two call sites.
  // // Debug-only rows appended after Log out on both layouts (mobile flat list + desktop
  // // menu pane): the screens gallery, the UI-kit gallery, a forced logout, and — in the
  // // gallery preview — the dev state control. Empty in release (all kDebugMode-gated).
  // List<Widget> _devMenuRows({bool menuPane = false}) => [
  // if (kDebugMode)
  // AppSettingsNavRowWidget(title: 'Screens gallery (dev)', menuPane: menuPane, onTap: () => _openSection(ScreensGalleryPage.route())),
  // if (kDebugMode) AppSettingsNavRowWidget(title: 'UI kit (dev)', menuPane: menuPane, onTap: () => _openSection(UiKitPage.route())),
  // if (kDebugMode && !widget.demo)
  // AppSettingsNavRowWidget(title: 'Force logout (dev)', menuPane: menuPane, onTap: () => unawaited(authRepository.logout(forced: true))),
  // if (kDebugMode && widget.demo) _devControl(),
  // ];

  // ---- Desktop: list-detail -------------------------------------------------

  Widget _wide(BuildContext context, SettingsRootState state) {
    return Scaffold(
      body: AppListDetailWidget(
        listPaneWidth: AppDimensionTokens.layout.settingsListPaneW,
        listPane: _menuPane(context, state),
        detailPane: _detailPane(context, state),
      ),
    );
  }

  Widget _menuPane(BuildContext context, SettingsRootState state) {
    AppSettingsNavRowWidget item(_Section section, String title, SvgGenImage icon, SvgGenImage selectedIcon) => AppSettingsNavRowWidget(
      title: title,
      icon: icon,
      selectedIcon: selectedIcon,
      selected: _selected == section,
      menuPane: true,
      onTap: () => setState(() => _selected = section),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // No divider under the pane header — the design's PaneHeader is borderless
        // (the section title sits directly over the list, seam only between groups).
        _SettingsPaneHeader(
          title: context.l10n.settings,
          leading: widget.inShell ? null : _backButton(),
          trailingInset: AppSpacingTokens.s8,
        ),
        // An M3 NavigationDrawer: destinations as stadium items on the pane
        // itself, transparent until selected, in the three groups the desktop
        // corpus separates with a line UNDER each group rather than with a card.
        // The line sits below the group's padding, so it never crosses a pill.
        //
        // The destinations SCROLL and `Log out` stays pinned to the foot. As one
        // unscrollable Column with a Spacer it clipped the last rows behind an
        // overflow stripe with no way to reach them, from 598px of window height
        // down (measured at 1280 wide: overflow = 598.4 - height, so 0.4px at 598
        // and 38px at 560). macOS opens its default window at 800x600 - four
        // pixels of headroom - and no desktop target here sets a minimum size.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _navGroup(context, [
                        item(_Section.account, context.l10n.settingsAccountTitle, NoxIcons.person, NoxIcons.personFill),
                        item(_Section.devices, context.l10n.settingsDevicesTitle, NoxIcons.devices, NoxIcons.devicesFill),
                      ]),
                      _navGroup(context, [
                        item(
                          _Section.notifications,
                          context.l10n.settingsNotificationsTitle,
                          NoxIcons.notifications,
                          NoxIcons.notificationsFill,
                        ),
                        item(_Section.appearance, context.l10n.settingsAppearanceTitle, NoxIcons.palette, NoxIcons.paletteFill),
                        item(_Section.language, context.l10n.settingsLanguageTitle, NoxIcons.language, NoxIcons.languageFill),
                      ]),
                      _navGroup(context, [
                        item(_Section.terms, context.l10n.settingsTermsTitle, NoxIcons.description, NoxIcons.descriptionFill),
                        item(_Section.about, context.l10n.settingsAboutTitle, NoxIcons.info, NoxIcons.infoFill),
                      ], last: true),
                    ],
                  ),
                ),
              ),
              AppSettingsNavRowWidget(
                title: context.l10n.logoutRow,
                icon: NoxIcons.logoutFill,
                danger: true,
                menuPane: true,
                onTap: _logout,
              ),
              SizedBox(height: AppSpacingTokens.s8),
              // ..._devMenuRows(menuPane: true),
            ],
          ),
        ),
      ],
    );
  }

  // Title of the selected detail section, mirroring the menu-pane item labels.
  String _sectionTitle(_Section section) => switch (section) {
    _Section.account => context.l10n.settingsAccountTitle,
    _Section.devices => context.l10n.settingsDevicesTitle,
    _Section.notifications => context.l10n.settingsNotificationsTitle,
    _Section.appearance => context.l10n.settingsAppearanceTitle,
    _Section.language => context.l10n.settingsLanguageTitle,
    _Section.terms => context.l10n.settingsTermsTitle,
    _Section.about => context.l10n.settingsAboutTitle,
  };

  Widget _detailPane(BuildContext context, SettingsRootState state) {
    final Widget body = switch (_selected) {
      _Section.account => ListView(
        padding: EdgeInsets.all(AppSpacingTokens.s16),
        children: [
          _identityCard(state, wide: true),
          // Design: the account QR + caption sit in a separate centred block BELOW the
          // identity card, on the plain detail-pane background (not inside the card).
        ],
      ),
      _Section.devices => const DevicesBody(),
      _Section.notifications => const NotificationsBody(),
      _Section.appearance => const AppearanceBody(),
      _Section.language => const LanguageBody(),
      _Section.terms => const TermsBody(),
      _Section.about => const AboutBody(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // PaneHeader: names the selected section (the detail pane has no AppBar of
        // its own), aligned with the menu pane's header height/style. Borderless like
        // the design's PaneHeader (no hairline under the section title).
        _SettingsPaneHeader(title: _sectionTitle(_selected)),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppDimensionTokens.layout.settingsMaxW),
              child: body,
            ),
          ),
        ),
      ],
    );
  }

  // ---- Shared ---------------------------------------------------------------

  // Context-side resolver for the inline name-edit error (was
  // SettingsRootState.nameError; the BLoC state no longer holds localized strings).
  String? _nameError(SettingsNameStatus status) => switch (status) {
    SettingsNameStatus.invalidCharset => context.l10n.usernameCharsetError,
    SettingsNameStatus.saveFailed => context.l10n.settingsNameSaveError,
    _ => null,
  };

  /// One menu-pane group: its items, a little breathing room, and the line that
  /// closes it. The last group draws no line - there is nothing under it to
  /// separate from.
  Widget _navGroup(BuildContext context, List<Widget> items, {bool last = false}) => Container(
    padding: EdgeInsets.only(bottom: AppSpacingTokens.s6),
    margin: EdgeInsets.only(bottom: AppSpacingTokens.s6),
    decoration: last
        ? null
        : BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: AppDimensionTokens.border.hairline),
            ),
          ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: items),
  );

  /// How far the centre-docked create FAB stands proud of the bottom bar, plus
  /// air. Scroll views hosted in the shell add it below their last item.
  ///
  /// A getter, not a `static final`: these tokens are ScreenUtil-scaled, and a
  /// static final is initialised once per isolate - it would freeze at whatever
  /// scale happened to be current the first time this screen built.
  static double get _dockedFabClearance => AppSpacingTokens.s40;

  /// The margin `AppSettingsGroupWidget` gives itself. Anything placed beside a
  /// group card uses it, so every card edge on the screen is the same edge.
  static EdgeInsets get _cardMargin =>
      EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s4, AppSpacingTokens.s16, AppSpacingTokens.s16);

  Widget _identityCard(SettingsRootState state, {required bool wide}) {
    return AppIdentityCardWidget(
      name: state.name,
      // The id is public since 032, so it is shown whole - there is no mask left
      // to lift and nothing for a reveal to reveal.
      rawId: state.rawId,
      initialLoading: state.initialLoading,
      editing: state.editing,
      onEditName: _startEdit,
      onCopy: _copyId,
      // Showing a QR of the identity used to hand over a bearer secret. The id
      // is public now and inviting a device is a different act, so the action
      // leads to the devices screen, where the invite is minted with a real
      // one-shot token.
      //
      // On desktop that is a pane selection, not a push: pushing a full-screen
      // page over the shell is how the rest of Settings would never behave.
      nameEditField: state.editing
          ? AppLabeledFieldWidget(
              controller: _nameController,
              focusNode: _nameFocusNode,
              label: context.l10n.usernameLabel,
              maxLength: 32,
              autofocus: true,
              errorText: _nameError(state.status),
              onChanged: (value) => _bloc.add(SettingsRootEvent.nameChanged(value)),
              onSubmitted: () => _bloc.add(const SettingsRootEvent.nameSubmitted()),
            )
          : null,
    );
  }

  // Widget _devControl() {
  // return Padding(
  // padding: EdgeInsets.all(AppSpacingTokens.s16),
  // child: Align(
  // alignment: Alignment.centerLeft,
  // child: OutlinedButton(
  // onPressed: () => Navigator.of(context).push(AppErrorPage.route(params: ErrorPageParams.fatal())),
  // child: const Text('Fatal (preview)'),
  // ),
  // ),
  // );
  // }
}

/// Desktop settings pane header (`titleLarge` label with an optional [leading] back
/// affordance) — shared by the menu pane (with the back button) and the detail pane
/// (title only). [trailingInset] preserves the small delta between the two (the menu
/// pane trims the right inset); it defaults to the detail pane's `s16`.
class _SettingsPaneHeader extends StatelessWidget {
  const _SettingsPaneHeader({required this.title, this.leading, this.trailingInset});

  final String title;
  final Widget? leading;
  final double? trailingInset;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s12, trailingInset ?? AppSpacingTokens.s16, AppSpacingTokens.s12),
      child: Row(
        children: [
          ?leading,
          Expanded(
            child: Text(title, style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface)),
          ),
        ],
      ),
    );
  }
}
