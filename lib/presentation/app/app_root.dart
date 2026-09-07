import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nox_app/data/sync/pair_request_service.dart';
import 'package:nox_app/design/app_text_style_tokens.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/person/pair_request.dart';
import 'package:nox_app/design/theme/app_theme.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/general/app_language.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/general/locale_controller.dart';
import 'package:nox_app/l10n/app_localizations.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/helpers/app_feedback_helper.dart';
import 'package:nox_app/presentation/pages/login_page/login_page.dart';
import 'package:nox_app/presentation/pages/pair_request_page/pair_request_page.dart';
import 'package:nox_app/presentation/pages/set_username_page/set_username_page.dart';
import 'package:nox_app/presentation/pages/splash_page/splash_page.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';

/// Root MaterialApp: theme from AppTheme, themeMode from AppRootBloc, design-scale
/// via ScreenUtil with OS font-scale neutralized. Entry is the [SplashPage]; the
/// app-state spine ([AppStateRepository] → [AppRootBloc]) drives top-level
/// navigation by swapping the root route on each applied state change.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late final AppRootBloc _bloc;
  final _navigatorKey = GlobalKey<NavigatorState>();

  StreamSubscription<List<PairRequest>>? _pairRequests;

  /// The request currently on screen, so a re-send of the same question - the
  /// server repeats every waiting one after each greeting - does not stack a
  /// second identical surface on top of the first.
  String? _askingAbout;

  // Whether the first app-state transition has already replaced the Splash home route.
  // The first transition uses pushReplacement; every later one clears the whole stack.
  bool _splashReplaced = false;

  @override
  void initState() {
    super.initState();
    _bloc = AppRootBloc()..add(const AppRootEvent.initialize());
    // Load the persisted UI language; nudges LocaleController.language, which
    // re-renders MaterialApp via the ValueListenableBuilder in build().
    LocaleController.instance.load();
    _watchPairRequests();
  }

  @override
  void dispose() {
    unawaited(_pairRequests?.cancel());
    _bloc.close();
    super.dispose();
  }

  /// Somebody is at the door (contract §8B).
  ///
  /// The subscription lives HERE rather than on the People screen because the
  /// question has to reach the owner wherever they are - in a chat, in the
  /// list, in settings. Only the owner is ever sent these, so nothing checks
  /// the role: a second place reasoning about ownership is a second place to
  /// disagree with the server about it.
  void _watchPairRequests() {
    if (!getIt.isRegistered<PairRequestService>()) return;
    _pairRequests = getIt<PairRequestService>().open.listen((_) => _askNext());
  }

  /// Opens the oldest open question, if none is on screen already.
  ///
  /// Called on every emission AND after each surface closes. Only reacting to
  /// emissions loses the second question: two people knocking while the phone
  /// is locked produces `[A]` then `[A, B]`, and the second list arrives while
  /// A is still on screen. Nothing emits again after A is answered, so B would
  /// wait out its five minutes unseen.
  void _askNext() {
    if (_askingAbout != null || !getIt.isRegistered<PairRequestService>()) return;
    final requests = getIt<PairRequestService>().current;
    if (requests.isEmpty) return;
    // Never over the pairing screen. A question that outlived a logout would
    // ask a signed-out device to let somebody into a server it no longer has a
    // session with.
    if (_bloc.state.appliedAppState.state != AppStateType.authorized) return;
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null || !navigatorContext.mounted) return;

    final request = requests.first;
    _askingAbout = request.requestId;
    // Read from the view rather than through MediaQuery.sizeOf: this runs from
    // a stream callback, and sizeOf would register the root Navigator as a
    // dependent - every resize and every keyboard would then rebuild the whole
    // navigator subtree for the rest of the session.
    final wide = MediaQueryData.fromView(View.of(navigatorContext)).size.width >= Constants.railBreakpoint;
    final surface = wide
        ? PairRequestPage.showAsDialog(navigatorContext, request)
        : Navigator.of(navigatorContext).push(PairRequestPage.route(request));
    unawaited(
      surface.whenComplete(() {
        _askingAbout = null;
        // A question may have been waiting behind this one.
        if (mounted) _askNext();
      }),
    );
  }

  Route<void>? _routeForState(AppStateType state) {
    switch (state) {
      case AppStateType.unauthorized:
        return LoginPage.route();
      case AppStateType.registrationPending:
        return SetUsernamePage.route();
      case AppStateType.authorized:
        return TabBarShell.route();
      case AppStateType.init:
        return null; // stay on Splash
    }
  }

  void _onAppStateRouting(BuildContext context, AppRootState state) {
    final navigator = _navigatorKey.currentState;
    final route = _routeForState(state.appliedAppState.state);
    // FR-016 extension point: a flow that owns its own navigation (a multi-step wizard,
    // a payment sheet) would veto the top-level stack replacement here — deliberately a
    // no-op for now, NOX has no such flow.
    if (navigator == null || route == null) return;
    // First transition away from Splash replaces it; any later auth boundary blows away
    // the whole stack (no back across the boundary).
    if (!_splashReplaced) {
      _splashReplaced = true;
      navigator.pushReplacement(route);
    } else {
      navigator.pushAndRemoveUntil(route, (_) => false);
    }
  }

  // One-shot session-expiry message, shown over the freshly-pushed Login. Runs in a
  // post-frame callback so it lands AFTER the routing push, on the navigator's
  // context (below MaterialApp → a ScaffoldMessenger is in scope).
  void _onSessionExpired(BuildContext context, AppRootState state) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigatorContext = _navigatorKey.currentContext;
      if (navigatorContext != null && navigatorContext.mounted) {
        showAppSnackBar(navigatorContext, text: navigatorContext.l10n.sessionExpiredMessage, error: true);
      }
    });
  }

  // Transient settings save-error notice: a theme persist failed and the bloc already
  // reverted the theme; surface "Could not save. Try again." over the current screen.
  void _onSettingsSaveError(BuildContext context, AppRootState state) {
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext != null && navigatorContext.mounted) {
      showAppSnackBar(navigatorContext, text: navigatorContext.l10n.settingsSaveError, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AppRootBloc>.value(
      value: _bloc,
      child: MultiBlocListener(
        listeners: [
          BlocListener<AppRootBloc, AppRootState>(
            listenWhen: (previous, current) => previous.appliedAppState.state != current.appliedAppState.state,
            listener: _onAppStateRouting,
          ),
          BlocListener<AppRootBloc, AppRootState>(
            // React when entering unauthorized-with-sessionExpired OR when the
            // sessionExpired flag flips false→true while ALREADY on unauthorized (a
            // forced logout from the Login screen — deferred 401 path), so the
            // "session expired" notice is never silently dropped.
            listenWhen: (previous, current) =>
                current.appliedAppState.state == AppStateType.unauthorized &&
                current.appliedAppState.sessionExpired &&
                (previous.appliedAppState.state != AppStateType.unauthorized || !previous.appliedAppState.sessionExpired),
            listener: _onSessionExpired,
          ),
          BlocListener<AppRootBloc, AppRootState>(
            listenWhen: (previous, current) => previous.settingsSaveErrorTick != current.settingsSaveErrorTick,
            listener: _onSettingsSaveError,
          ),
        ],
        child: BlocBuilder<AppRootBloc, AppRootState>(
          buildWhen: (previous, current) => previous.themeMode != current.themeMode,
          builder: (context, state) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
              child: ScreenUtilInit(
                designSize: Constants.designSize,
                // Clamp `.sp` (≤ 1.0) so type never balloons on a wide desktop window
                // (replaces screenutil's unbounded width-only default; `minTextAdapt`
                // would be a dead no-op once a resolver is set). See the resolver doc.
                fontSizeResolver: AppTextStyleTokens.fontSizeResolver,
                builder: (context, child) {
                  return ValueListenableBuilder<AppLanguage>(
                    valueListenable: LocaleController.instance.language,
                    builder: (context, _, _) => MaterialApp(
                      onGenerateTitle: (context) => context.l10n.appName,
                      navigatorKey: _navigatorKey,
                      theme: AppTheme.light(),
                      darkTheme: AppTheme.dark(),
                      themeMode: state.themeMode,
                      locale: LocaleController.instance.locale,
                      localizationsDelegates: AppLocalizations.localizationsDelegates,
                      supportedLocales: AppLocalizations.supportedLocales,
                      scrollBehavior: const MaterialScrollBehavior().copyWith(
                        dragDevices: {
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.touch,
                          PointerDeviceKind.trackpad,
                          PointerDeviceKind.stylus,
                        },
                      ),
                      // Inner MediaQuery re-pins TextScaler inside MaterialApp's subtree so the
                      // OS font scale cannot leak back into AppBar/Scaffold/etc (blueprint 06 §3.2).
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
                        child: child ?? const SizedBox.shrink(),
                      ),
                      home: const SplashPage(),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
