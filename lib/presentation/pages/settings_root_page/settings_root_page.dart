import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/helpers/app_feedback_helper.dart';
import 'package:nox_app/presentation/pages/about_page/about_body.dart';
import 'package:nox_app/presentation/pages/about_page/about_page.dart';
import 'package:nox_app/presentation/pages/appearance_page/appearance_body.dart';
import 'package:nox_app/presentation/pages/appearance_page/appearance_page.dart';
import 'package:nox_app/presentation/pages/base/base_state_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page_params.dart';
import 'package:nox_app/presentation/pages/language_page/language_body.dart';
import 'package:nox_app/presentation/pages/language_page/language_page.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_body.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_page.dart';
import 'package:nox_app/presentation/pages/screens_gallery_page/screens_gallery_page.dart';
import 'package:nox_app/presentation/pages/settings_root_page/bloc/settings_root_bloc.dart';
import 'package:nox_app/presentation/pages/splash_page/splash_page.dart';
import 'package:nox_app/presentation/pages/terms_page/terms_body.dart';
import 'package:nox_app/presentation/pages/terms_page/terms_page.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_labeled_field_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_identity_card_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_logout_dialog_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_qr_surface_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_nav_row_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_list_detail_widget.dart';

/// Desktop settings sections (the list-detail menu items).
enum _Section { account, notifications, appearance, language, terms, about }

/// 7.1 Settings root — the Settings tab body. Mobile: a flat list (identity card +
/// nav rows + Log out). Desktop: a list-detail (menu pane 340 + detail pane ≤680,
/// selection swaps the pane without push; the raw ID is never revealed, an inline
/// account QR is shown instead). Settings rows open the real 7.2–7.7 subscreens;
/// Log out → real 1.1 Splash. Owns [SettingsRootBloc]. `[inShell]` suppresses the
/// back affordance when hosted as a shell tab.
class SettingsRootPage extends StatefulWidget {
  const SettingsRootPage({super.key, this.demo = false, this.inShell = false, this.forceWide});

  final bool demo;
  final bool inShell;

  /// When hosted in the shell, the shell's layout decision (rail vs bottom bar) is
  /// passed down so the body follows it instead of re-measuring its rail-narrowed
  /// width. Null (standalone) → self-measure against the breakpoint.
  final bool? forceWide;

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
  }

  @override
  void dispose() {
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
    // Fire-and-forget the clipboard write; the confirmation is instant.
    unawaited(Clipboard.setData(const ClipboardData(text: SettingsRootBloc.mockRawId)));
    showAppSnackBar(context, text: TextConstants.copiedToClipboard);
  }

  Future<void> _logout() async {
    final confirmed = await AppLogoutDialogWidget.show(context);
    if (confirmed != true || !mounted) return;
    if (widget.demo) {
      // Gallery preview: hop to the standalone (demo) Splash without touching real state.
      Navigator.of(context).push(SplashPage.routeDemo());
    } else {
      // Real flow: full wipe + re-derive app state; the spine returns to Login.
      await authRepository.logout();
    }
  }

  void _openSection(Route<void> route) => Navigator.of(context).push(route);

  Widget _backOrNull(VoidCallback onPressed) => widget.inShell
      ? const SizedBox.shrink()
      : IconButton(tooltip: TextConstants.tooltipBack, icon: AppIconWidget(NoxIcons.arrowBack), onPressed: onPressed);

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
      appBar: AppBar(
        leading: widget.inShell
            ? null
            : IconButton(
                tooltip: TextConstants.tooltipBack,
                icon: AppIconWidget(NoxIcons.arrowBack),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
        title: const Text(TextConstants.settings),
      ),
      body: ListView(
        children: [
          Padding(
            padding: EdgeInsets.all(AppSpacingTokens.s16),
            child: _identityCard(state, revealable: true, showInlineQr: false, wide: false),
          ),
          AppSettingsNavRowWidget(title: TextConstants.settingsNotificationsTitle, onTap: () => _openSection(NotificationsPage.route())),
          AppSettingsNavRowWidget(title: TextConstants.settingsAppearanceTitle, onTap: () => _openSection(AppearancePage.route())),
          AppSettingsNavRowWidget(title: TextConstants.settingsLanguageTitle, onTap: () => _openSection(LanguagePage.route())),
          AppSettingsNavRowWidget(title: TextConstants.settingsTermsTitle, onTap: () => _openSection(TermsPage.route())),
          AppSettingsNavRowWidget(title: TextConstants.settingsAboutTitle, onTap: () => _openSection(AboutPage.route())),
          Divider(height: AppDimensionTokens.border.hairline),
          AppSettingsNavRowWidget(title: TextConstants.logoutRow, color: Theme.of(context).colorScheme.error, onTap: _logout),
          if (kDebugMode) AppSettingsNavRowWidget(title: 'Screens gallery (dev)', onTap: () => _openSection(ScreensGalleryPage.route())),
          if (kDebugMode && !widget.demo)
            AppSettingsNavRowWidget(title: 'Force logout (dev)', onTap: () => unawaited(authRepository.logout(forced: true))),
          if (kDebugMode && widget.demo) _devControl(),
        ],
      ),
    );
  }

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
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    AppSettingsNavRowWidget item(_Section section, String title) =>
        AppSettingsNavRowWidget(title: title, selected: _selected == section, onTap: () => setState(() => _selected = section));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s12, AppSpacingTokens.s8, AppSpacingTokens.s12),
          child: Row(
            children: [
              if (!widget.inShell) _backOrNull(() => Navigator.of(context).maybePop()),
              Expanded(
                child: Text(TextConstants.settings, style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface)),
              ),
            ],
          ),
        ),
        Divider(height: AppDimensionTokens.border.hairline),
        // Grouped nav items (Account / preferences / legal), with the destructive
        // Log out row pinned to the bottom via a Spacer.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Group 1: Account.
              item(_Section.account, TextConstants.settingsAccountTitle),
              Divider(height: AppDimensionTokens.border.hairline),
              // Group 2: Notifications, Appearance, Language.
              item(_Section.notifications, TextConstants.settingsNotificationsTitle),
              item(_Section.appearance, TextConstants.settingsAppearanceTitle),
              item(_Section.language, TextConstants.settingsLanguageTitle),
              Divider(height: AppDimensionTokens.border.hairline),
              // Group 3: Terms, About.
              item(_Section.terms, TextConstants.settingsTermsTitle),
              item(_Section.about, TextConstants.settingsAboutTitle),
              const Spacer(),
              AppSettingsNavRowWidget(title: TextConstants.logoutRow, color: colorScheme.error, onTap: _logout),
              if (kDebugMode)
                AppSettingsNavRowWidget(title: 'Screens gallery (dev)', onTap: () => _openSection(ScreensGalleryPage.route())),
              if (kDebugMode && !widget.demo)
                AppSettingsNavRowWidget(title: 'Force logout (dev)', onTap: () => unawaited(authRepository.logout(forced: true))),
              if (kDebugMode && widget.demo) _devControl(),
            ],
          ),
        ),
      ],
    );
  }

  // Title of the selected detail section, mirroring the menu-pane item labels.
  String _sectionTitle(_Section section) => switch (section) {
    _Section.account => TextConstants.settingsAccountTitle,
    _Section.notifications => TextConstants.settingsNotificationsTitle,
    _Section.appearance => TextConstants.settingsAppearanceTitle,
    _Section.language => TextConstants.settingsLanguageTitle,
    _Section.terms => TextConstants.settingsTermsTitle,
    _Section.about => TextConstants.settingsAboutTitle,
  };

  Widget _detailPane(BuildContext context, SettingsRootState state) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final Widget body = switch (_selected) {
      _Section.account => ListView(
        padding: EdgeInsets.all(AppSpacingTokens.s16),
        children: [_identityCard(state, revealable: false, showInlineQr: true, wide: true)],
      ),
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
        // its own), aligned with the menu pane's header height/style.
        Padding(
          padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s12, AppSpacingTokens.s16, AppSpacingTokens.s12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(_sectionTitle(_selected), style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface)),
          ),
        ),
        Divider(height: AppDimensionTokens.border.hairline),
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

  Widget _identityCard(SettingsRootState state, {required bool revealable, required bool showInlineQr, required bool wide}) {
    return AppIdentityCardWidget(
      name: state.name,
      maskedId: state.maskedId,
      rawId: SettingsRootBloc.mockRawId,
      revealable: revealable,
      showInlineQr: showInlineQr,
      initialLoading: state.initialLoading,
      editing: state.editing,
      idRevealed: state.idRevealed,
      onToggleReveal: () => _bloc.add(const SettingsRootEvent.idRevealToggled()),
      onEditName: _startEdit,
      onCopy: _copyId,
      onShowQr: () => showIdQr(context, data: SettingsRootBloc.mockRawId, wide: wide),
      nameEditField: state.editing
          ? AppLabeledFieldWidget(
              controller: _nameController,
              focusNode: _nameFocusNode,
              label: TextConstants.usernameLabel,
              maxLength: 32,
              autofocus: true,
              errorText: state.nameError,
              checking: state.isChecking,
              onChanged: (value) => _bloc.add(SettingsRootEvent.nameChanged(value)),
              onSubmitted: () => _bloc.add(const SettingsRootEvent.nameSubmitted()),
            )
          : null,
    );
  }

  Widget _devControl() {
    return Padding(
      padding: EdgeInsets.all(AppSpacingTokens.s16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: () => Navigator.of(context).push(AppErrorPage.route(params: ErrorPageParams.fatal())),
          child: const Text('Fatal (preview)'),
        ),
      ),
    );
  }
}
