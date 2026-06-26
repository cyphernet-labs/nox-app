import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/base/base_state_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page_params.dart';
import 'package:nox_app/presentation/pages/placeholder/route_placeholder_page.dart';
import 'package:nox_app/presentation/pages/set_username_page/bloc/set_username_bloc.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_labeled_field_widget.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_onboard_card_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_splash_hairline_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_window_titlebar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_wordmark_widget.dart';

/// 2.3 Set username — optional rename of the public label, pre-filled with the
/// server-assigned `User<random>`. Client charset validation + debounced
/// case-sensitive uniqueness; `Done` / `Skip`. Desktop reuses the onboarding card;
/// mobile uses the wordmark AppBar. Owns [SetUsernameBloc].
class SetUsernamePage extends StatefulWidget {
  const SetUsernamePage({super.key, this.demo = false});

  final bool demo;

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const SetUsernamePage(),
    settings: const RouteSettings(name: '/onboarding/set-username'),
  );

  /// Gallery entry: adds the dev save-outcome selector.
  static Route<void> routeDemo() => MaterialPageRoute<void>(
    builder: (_) => const SetUsernamePage(demo: true),
    settings: const RouteSettings(name: '/onboarding/set-username'),
  );

  @override
  State<SetUsernamePage> createState() => _SetUsernamePageState();
}

class _SetUsernamePageState extends BaseStatePage<SetUsernamePage> {
  late final SetUsernameBloc _bloc;
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  UsernameOutcome _outcome = UsernameOutcome.success;

  @override
  void initState() {
    super.initState();
    _bloc = SetUsernameBloc(demo: widget.demo);
    _controller = TextEditingController(text: _bloc.state.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _bloc.close();
    super.dispose();
  }

  void _done() => _bloc.add(SetUsernameEvent.doneRequested(outcome: _outcome));

  // Both Done and Skip go through the bloc, so they share the single `submitting`
  // state (no widget-local re-entry flag). Skip keeps the server-assigned name.
  void _skip() => _bloc.add(const SetUsernameEvent.skipRequested());

  void _onStatus(BuildContext context, SetUsernameState state) {
    switch (state.status) {
      case UsernameStatus.navSuccess:
        Navigator.of(context).push(RoutePlaceholderPage.route(destinationLabel: 'Chats shell (4.1)'));
        _bloc.add(const SetUsernameEvent.navigationHandled());
      case UsernameStatus.navFatal:
        Navigator.of(context).push(AppErrorPage.route(params: ErrorPageParams.fatal()));
        _bloc.add(const SetUsernameEvent.navigationHandled());
      case UsernameStatus.raceTaken:
        _focusNode.requestFocus();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SetUsernameBloc>.value(
      value: _bloc,
      child: BlocConsumer<SetUsernameBloc, SetUsernameState>(
        listenWhen: (previous, current) => previous.status != current.status,
        listener: _onStatus,
        builder: (context, state) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= Constants.railBreakpoint;
              return wide ? _wide(context, state) : _narrow(context, state);
            },
          );
        },
      ),
    );
  }

  Widget _narrow(BuildContext context, SetUsernameState state) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const AppWordmarkWidget(), bottom: const AppSplashHairlineWidget()),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s24, AppSpacingTokens.s16, 0),
                child: _field(state),
              ),
            ),
            Padding(padding: EdgeInsets.all(AppSpacingTokens.s16), child: _actions(context, state)),
          ],
        ),
      ),
    );
  }

  Widget _wide(BuildContext context, SetUsernameState state) {
    return Scaffold(
      body: Column(
        children: [
          const AppWindowTitlebarWidget(subtitle: 'Set up'),
          Expanded(
            child: AppOnboardCardWidget(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(state),
                  SizedBox(height: AppSpacingTokens.s24),
                  _actions(context, state),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(SetUsernameState state) {
    return AppLabeledFieldWidget(
      controller: _controller,
      focusNode: _focusNode,
      label: TextConstants.usernameLabel,
      maxLength: 32,
      helperText: TextConstants.usernameHelper,
      placeholder: TextConstants.usernameHint,
      errorText: state.errorText,
      checking: state.isChecking,
      enabled: !state.isSubmitting,
      onChanged: (value) => _bloc.add(SetUsernameEvent.nameChanged(value)),
    );
  }

  Widget _actions(BuildContext context, SetUsernameState state) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: state.canSubmit && !state.isSubmitting ? _done : null,
            child: state.isSubmitting
                ? AppSpinnerWidget(size: AppDimensionTokens.icon.md, color: colorScheme.onPrimary)
                : const Text(TextConstants.actionDone),
          ),
        ),
        TextButton(onPressed: state.isSubmitting ? null : _skip, child: const Text(TextConstants.actionSkip)),
        if (kDebugMode && widget.demo) _OutcomeControl(value: _outcome, onChanged: (value) => setState(() => _outcome = value)),
      ],
    );
  }
}

/// Dev-only save-outcome selector (gallery preview).
class _OutcomeControl extends StatelessWidget {
  const _OutcomeControl({required this.value, required this.onChanged});

  final UsernameOutcome value;
  final ValueChanged<UsernameOutcome> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: AppSpacingTokens.s8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Outcome:'),
          SizedBox(width: AppSpacingTokens.s8),
          DropdownButton<UsernameOutcome>(
            value: value,
            onChanged: (selected) {
              if (selected != null) onChanged(selected);
            },
            items: const [
              DropdownMenuItem(value: UsernameOutcome.success, child: Text('success')),
              DropdownMenuItem(value: UsernameOutcome.raceTaken, child: Text('race taken')),
              DropdownMenuItem(value: UsernameOutcome.fatal, child: Text('fatal')),
            ],
          ),
        ],
      ),
    );
  }
}
