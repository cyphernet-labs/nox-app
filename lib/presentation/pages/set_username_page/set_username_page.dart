import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nox_app/presentation/widgets/app_dev_scenario_dropdown.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/pages/base/base_state_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page_params.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';
import 'package:nox_app/presentation/pages/set_username_page/bloc/set_username_bloc.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_labeled_field_widget.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_onboarding_scaffold_widget.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_primary_button_widget.dart';

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
        Navigator.of(context).push(TabBarShell.route());
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
        builder: (context, state) =>
            AppOnboardingScaffoldWidget(subtitle: 'Set up', field: _field(context, state), actions: _actions(context, state)),
      ),
    );
  }

  Widget _field(BuildContext context, SetUsernameState state) {
    return AppLabeledFieldWidget(
      controller: _controller,
      focusNode: _focusNode,
      label: context.l10n.usernameLabel,
      maxLength: 32,
      helperText: context.l10n.usernameHelper,
      placeholder: context.l10n.usernameHint,
      errorText: _errorText(context, state.status),
      checking: state.isChecking,
      enabled: !state.isSubmitting,
      onChanged: (value) => _bloc.add(SetUsernameEvent.nameChanged(value)),
    );
  }

  String? _errorText(BuildContext context, UsernameStatus status) => switch (status) {
    UsernameStatus.invalidCharset => context.l10n.usernameCharsetError,
    UsernameStatus.raceTaken => context.l10n.nameTakenError,
    _ => null,
  };

  Widget _actions(BuildContext context, SetUsernameState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppPrimaryButtonWidget(
          label: context.l10n.actionDone,
          onPressed: state.canSubmit && !state.isSubmitting ? _done : null,
          loading: state.isSubmitting,
        ),
        TextButton(onPressed: state.isSubmitting ? null : _skip, child: Text(context.l10n.actionSkip)),
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
      child: AppDevScenarioDropdown<UsernameOutcome>(
        value: value,
        label: 'Outcome:',
        items: const {UsernameOutcome.success: 'success', UsernameOutcome.raceTaken: 'race taken', UsernameOutcome.fatal: 'fatal'},
        onChanged: onChanged,
      ),
    );
  }
}
