import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/domain/model/person/person_model.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/pages/people_page/bloc/people_bloc.dart';
import 'package:nox_app/presentation/widgets/settings/app_invite_card_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_owner_badge_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_group_widget.dart';

/// 7.4 People, chrome-less so the same body fills the desktop Settings detail
/// pane (7.1) — the split every settings leaf uses.
///
/// Reachable only by the owner: inviting somebody onto this machine is the
/// operator's decision, and the server refuses everyone else. The screen is
/// hidden rather than shown-and-refused, because a refusal on the wire exists
/// for the protocol's honesty, not as a way to tell a person they may not.
class PeopleBody extends StatefulWidget {
  const PeopleBody({super.key, this.initialState});

  /// Seeds a state a golden could not otherwise reach: the list comes from a
  /// server, and there is none under test.
  @visibleForTesting
  final PeopleState? initialState;

  @override
  State<PeopleBody> createState() => _PeopleBodyState();
}

class _PeopleBodyState extends State<PeopleBody> {
  late final PeopleBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = PeopleBloc();
    // A seeded state skips the load entirely; the real flow always loads.
    if (widget.initialState == null) _bloc.add(const PeopleEvent.initialize());
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PeopleBloc, PeopleState>(
      bloc: _bloc,
      builder: (context, live) {
        final state = widget.initialState ?? live;
        if (state.loading) return const Center(child: CircularProgressIndicator());
        if (state.failed && state.people.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacingTokens.s16),
              child: Text(context.l10n.peopleError, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            ),
          );
        }
        return ListView(
          padding: EdgeInsets.all(AppSpacingTokens.s16),
          children: [
            if (state.inviteLink != null) ...[
              AppInviteCardWidget(
                link: state.inviteLink!,
                message: context.l10n.peopleInviteMessage,
                onDismiss: () => _bloc.add(const PeopleEvent.inviteDismissed()),
              ),
              SizedBox(height: AppSpacingTokens.s16),
            ],
            // A failure with rows already on screen has to be visible too:
            // rendered only when the list is empty, it would read as a dead
            // button on every other attempt.
            if (state.failed && state.people.isNotEmpty) ...[
              _error(context, context.l10n.peopleError),
              SizedBox(height: AppSpacingTokens.s16),
            ],
            if (state.inviteFailed) ...[_error(context, context.l10n.peopleInviteError), SizedBox(height: AppSpacingTokens.s16)],
            if (state.self != null) AppSettingsGroupWidget(children: [_PersonRow(person: state.self!)]),
            SizedBox(height: AppSpacingTokens.s16),
            if (state.others.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacingTokens.s16),
                child: Text(context.l10n.peopleEmpty, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              )
            else
              AppSettingsGroupWidget(children: [for (final person in state.others) _PersonRow(person: person)]),
            SizedBox(height: AppSpacingTokens.s16),
            FilledButton(
              onPressed: state.inviting ? null : () => _bloc.add(const PeopleEvent.inviteRequested()),
              child: Text(context.l10n.peopleInvite),
            ),
          ],
        );
      },
    );
  }

  Widget _error(BuildContext context, String message) => Text(
    message,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
  );
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person});

  final PersonModel person;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s16, vertical: AppSpacingTokens.s12),
      child: Row(
        children: [
          // Wrap, not two flexible children: the name keeps the full width and
          // the badge drops to its own line rather than squeezing it — the same
          // fix the identity card needed.
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacingTokens.s8,
              runSpacing: AppSpacingTokens.s4,
              children: [
                Text(person.label, style: theme.textTheme.bodyLarge),
                if (person.isOwner) const AppOwnerBadgeWidget(),
              ],
            ),
          ),
          if (person.isSelf) Text(context.l10n.peopleYou, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }
}
