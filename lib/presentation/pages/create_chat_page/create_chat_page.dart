import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/base/base_state_page.dart';
import 'package:nox_app/presentation/pages/create_chat_page/bloc/create_chat_bloc.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page_params.dart';
import 'package:nox_app/presentation/pages/placeholder/route_placeholder_page.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_labeled_field_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

/// 6.1 Create chat — a name form with debounced uniqueness (unrestricted charset).
/// Mobile: a full-screen pushed screen (AppBar `New chat` + back). Desktop: a
/// centered modal `Dialog` (≈460) over a scrim with `Cancel` + `Create`
/// (corpus `07-create.md`). Real `showDialog` from the chats shell is a later
/// milestone (`// TODO(M3)`). Owns [CreateChatBloc].
class CreateChatPage extends StatefulWidget {
  const CreateChatPage({super.key, this.demo = false});

  final bool demo;

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const CreateChatPage(),
    settings: const RouteSettings(name: '/create/chat'),
  );

  /// Gallery entry: adds the dev create-outcome selector.
  static Route<void> routeDemo() => MaterialPageRoute<void>(
    builder: (_) => const CreateChatPage(demo: true),
    settings: const RouteSettings(name: '/create/chat'),
  );

  @override
  State<CreateChatPage> createState() => _CreateChatPageState();
}

class _CreateChatPageState extends BaseStatePage<CreateChatPage> {
  late final CreateChatBloc _bloc;
  final TextEditingController _controller = TextEditingController();
  CreateChatOutcome _outcome = CreateChatOutcome.success;

  @override
  void initState() {
    super.initState();
    _bloc = CreateChatBloc();
  }

  @override
  void dispose() {
    _controller.dispose();
    _bloc.close();
    super.dispose();
  }

  void _create() => _bloc.add(CreateChatEvent.createRequested(outcome: _outcome));

  void _cancel() => Navigator.of(context).maybePop();

  void _onStatus(BuildContext context, CreateChatState state) {
    switch (state.status) {
      case CreateChatStatus.navSuccess:
        Navigator.of(context).push(RoutePlaceholderPage.route(destinationLabel: 'Chat thread (5.2)'));
      case CreateChatStatus.navFatal:
        Navigator.of(context).push(AppErrorPage.route(params: ErrorPageParams.fatal()));
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CreateChatBloc>.value(
      value: _bloc,
      child: BlocConsumer<CreateChatBloc, CreateChatState>(
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

  Widget _narrow(BuildContext context, CreateChatState state) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: TextConstants.tooltipBack, icon: AppIconWidget(NoxIcons.arrowBack), onPressed: _cancel),
        title: const Text(TextConstants.tooltipCreateChat),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(padding: EdgeInsets.all(AppSpacingTokens.s16), child: _field(state)),
            ),
            Padding(
              padding: EdgeInsets.all(AppSpacingTokens.s16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: double.infinity, child: _createButton(context, state)),
                  if (kDebugMode && widget.demo) _outcomeControl(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wide(BuildContext context, CreateChatState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _cancel,
              child: ColoredBox(color: colorScheme.scrim.withValues(alpha: 0.4)),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: EdgeInsets.all(AppSpacingTokens.s24),
                child: Material(
                  color: colorScheme.surfaceContainerHigh,
                  elevation: NoxElevation.level5,
                  borderRadius: BorderRadius.circular(NoxRadius.xl),
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacingTokens.s24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(TextConstants.tooltipCreateChat, style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface)),
                        SizedBox(height: AppSpacingTokens.s16),
                        _field(state),
                        SizedBox(height: AppSpacingTokens.s24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(onPressed: state.isSubmitting ? null : _cancel, child: const Text(TextConstants.actionCancel)),
                            SizedBox(width: AppSpacingTokens.s8),
                            _createButton(context, state),
                          ],
                        ),
                        if (kDebugMode && widget.demo) _outcomeControl(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(CreateChatState state) {
    return AppLabeledFieldWidget(
      controller: _controller,
      label: TextConstants.createChatNameLabel,
      maxLength: 64,
      placeholder: TextConstants.createChatNameHint,
      errorText: state.errorText,
      checking: state.isChecking,
      enabled: !state.isSubmitting,
      onChanged: (value) => _bloc.add(CreateChatEvent.nameChanged(value)),
    );
  }

  Widget _createButton(BuildContext context, CreateChatState state) {
    final colorScheme = Theme.of(context).colorScheme;
    return FilledButton(
      onPressed: state.canSubmit && !state.isSubmitting ? _create : null,
      child: state.isSubmitting ? AppSpinnerWidget(size: 18, color: colorScheme.onPrimary) : const Text(TextConstants.actionCreate),
    );
  }

  Widget _outcomeControl() {
    return Padding(
      padding: EdgeInsets.only(top: AppSpacingTokens.s8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Outcome:'),
          SizedBox(width: AppSpacingTokens.s8),
          DropdownButton<CreateChatOutcome>(
            value: _outcome,
            onChanged: (selected) {
              if (selected != null) setState(() => _outcome = selected);
            },
            items: const [
              DropdownMenuItem(value: CreateChatOutcome.success, child: Text('success')),
              DropdownMenuItem(value: CreateChatOutcome.network, child: Text('network error')),
              DropdownMenuItem(value: CreateChatOutcome.fatal, child: Text('fatal')),
            ],
          ),
        ],
      ),
    );
  }
}
