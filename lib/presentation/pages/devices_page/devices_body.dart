import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/domain/model/device/device_model.dart';
import 'package:nox_app/general/formatters/date_formatter.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/pages/devices_page/bloc/devices_bloc.dart';
import 'package:nox_app/presentation/widgets/settings/app_invite_card_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_group_widget.dart';

/// 7.8 Devices, chrome-less so the same body fills the desktop Settings detail
/// pane (7.1) — the split every settings leaf uses.
class DevicesBody extends StatefulWidget {
  const DevicesBody({super.key, this.initialState});

  /// Seeds a state a golden could not otherwise reach: the list comes from a
  /// server, and there is none under test.
  @visibleForTesting
  final DevicesState? initialState;

  @override
  State<DevicesBody> createState() => _DevicesBodyState();
}

class _DevicesBodyState extends State<DevicesBody> {
  late final DevicesBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = DevicesBloc();
    // A seeded state skips the load entirely; the real flow always loads.
    if (widget.initialState == null) _bloc.add(const DevicesEvent.initialize());
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DevicesBloc, DevicesState>(
      bloc: _bloc,
      builder: (context, live) {
        final state = widget.initialState ?? live;
        if (state.loading) return const Center(child: CircularProgressIndicator());
        if (state.failed && state.devices.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacingTokens.s16),
              child: Text(context.l10n.devicesError, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            ),
          );
        }
        return ListView(
          // Vertical only. The group card sets the screen inset itself, with its
          // own 16 margin - that is what indents it in Notifications too - so a
          // horizontal padding here as well pushed the device cards out to 32
          // while the button below stayed at 16, and the two edges did not line
          // up. Everything that is not a group card is inset explicitly.
          padding: EdgeInsets.symmetric(vertical: AppSpacingTokens.s16),
          children: [
            if (state.inviteLink != null) ...[
              _inset(
                AppInviteCardWidget(
                  link: state.inviteLink!,
                  message: context.l10n.devicesInviteMessage,
                  onDismiss: () => _bloc.add(const DevicesEvent.inviteDismissed()),
                ),
              ),
              SizedBox(height: AppSpacingTokens.s16),
            ],
            // A failed revoke used to be invisible: the error was rendered only
            // when the list was empty, so a person tapped Revoke, saw the row
            // stay, and had no idea whether it worked.
            //
            // Its own sentence, not the list's. The two states are separate
            // because they answer different questions, and pointing both at
            // "Couldn't load your devices." puts the blame for a revoke that
            // did not happen on a list that loaded perfectly well.
            if (state.actionFailed) ...[
              _inset(
                Text(
                  context.l10n.devicesRevokeError,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
              SizedBox(height: AppSpacingTokens.s16),
            ],
            // The list is there but the last read of it failed - the rows below
            // are the previous answer, so this says so rather than replacing
            // them with a full-screen error.
            if (state.failed && state.devices.isNotEmpty) ...[
              _inset(
                Text(
                  context.l10n.devicesError,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
              SizedBox(height: AppSpacingTokens.s16),
            ],
            // A silent failure here reads as a dead button: the person taps
            // "Add a device" and nothing at all happens.
            if (state.inviteFailed) ...[
              _inset(
                Text(
                  context.l10n.devicesInviteError,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
              SizedBox(height: AppSpacingTokens.s16),
            ],
            // ONE group, this device first. It used to be two - one of them
            // holding a single row - and two cards with a gap between them read as
            // two unrelated sections rather than as one list of this person's
            // devices. What sets the current one apart is that it says so and
            // comes first, which is enough; a whole separate card said more than
            // the difference is worth.
            //
            // And no "no other devices" line when this is the only one: by the
            // time the list renders the answer is settled - loading has its own
            // spinner and a failed read its own sentence - so it would state what
            // the screen already shows.
            if (state.current != null || state.others.isNotEmpty)
              AppSettingsGroupWidget(
                children: [
                  for (final device in [if (state.current != null) state.current!, ...state.others])
                    _DeviceRow(device: device, onRevoke: () => _confirmRevoke(device)),
                ],
              ),
            _inset(FilledButton(onPressed: () => _bloc.add(const DevicesEvent.inviteRequested()), child: Text(context.l10n.devicesAdd))),
          ],
        );
      },
    );
  }

  /// The horizontal inset the group card gives itself, for the children that are
  /// not group cards, so every edge on the screen lines up.
  Widget _inset(Widget child) => Padding(
    padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s16),
    child: child,
  );

  Future<void> _confirmRevoke(DeviceModel device) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(device.isCurrent ? l10n.logoutDialogTitle : l10n.devicesRevokeTitle),
        // Revoking the device in your hand is a logout, and it reads
        // differently from cutting off a tablet you no longer have.
        // Revoking your own device IS logout, so it has to read like logout -
        // the weaker wording undersold an action that ends the session and
        // cannot be undone without a new pairing link.
        content: Text(device.isCurrent ? l10n.logoutDialogMessage : l10n.devicesRevokeMessage),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.actionCancel)),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(l10n.devicesRevoke)),
        ],
      ),
    );
    if (confirmed ?? false) _bloc.add(DevicesEvent.revokeRequested(device.deviceKey));
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.onRevoke});

  final DeviceModel device;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      // Platform plus two moments, never the key: 32 bytes of base64 look
      // identical across five rows, and a person has to recognise their own.
      //
      // `This device` is an annotation on the name, not part of it, and is
      // toned down to read that way - glued on in the same colour it looked
      // like a device called "iPhone · This device".
      title: device.isCurrent
          ? Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: _platformName(device.platform)),
                  TextSpan(
                    text: ' · ${l10n.devicesCurrent}',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : Text(_platformName(device.platform)),
      subtitle: Text(
        '${l10n.devicesPairedAt(DateFormatter.momentShort(device.pairedAt, l10n: l10n))} · '
        '${l10n.devicesLastSeen(DateFormatter.momentShort(device.lastSeenAt, l10n: l10n))}',
      ),
      // Destructive, and irreversible: revoking a device cannot be undone without
      // a new pairing link, and revoking THIS one signs you out. It was rendered
      // in the brand accent - the same teal as `Add a device` right below it -
      // which is the colour this app uses for the thing it wants you to do. Log
      // out already sits in `error` for exactly this reason.
      trailing: TextButton(
        onPressed: onRevoke,
        style: TextButton.styleFrom(foregroundColor: colorScheme.error),
        child: Text(l10n.devicesRevoke),
      ),
    );
  }

  static String _platformName(String platform) => switch (platform) {
    'ios' => 'iPhone',
    'android' => 'Android',
    'macos' => 'macOS',
    'windows' => 'Windows',
    'linux' => 'Linux',
    _ => 'Device',
  };
}
