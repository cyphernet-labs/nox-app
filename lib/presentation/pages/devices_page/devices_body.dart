import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/domain/model/device/device_model.dart';
import 'package:nox_app/general/formatters/date_formatter.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/pages/devices_page/bloc/devices_bloc.dart';
import 'package:nox_app/presentation/widgets/settings/app_qr_surface_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_group_widget.dart';

/// 7.3 Devices, chrome-less so the same body fills the desktop Settings detail
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
          padding: EdgeInsets.all(AppSpacingTokens.s16),
          children: [
            if (state.inviteLink != null) ...[
              _InviteCard(link: state.inviteLink!, onDismiss: () => _bloc.add(const DevicesEvent.inviteDismissed())),
              SizedBox(height: AppSpacingTokens.s16),
            ],
            // A silent failure here reads as a dead button: the person taps
            // "Add a device" and nothing at all happens.
            // A failed revoke used to be invisible: the error was rendered only
            // when the list was empty, so a person tapped Revoke, saw the row
            // stay, and had no idea whether it worked.
            if (state.failed && state.devices.isNotEmpty) ...[
              Text(
                context.l10n.devicesError,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
              SizedBox(height: AppSpacingTokens.s16),
            ],
            if (state.inviteFailed) ...[
              Text(
                context.l10n.devicesInviteError,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
              SizedBox(height: AppSpacingTokens.s16),
            ],
            if (state.current != null)
              AppSettingsGroupWidget(
                children: [_DeviceRow(device: state.current!, onRevoke: () => _confirmRevoke(state.current!))],
              ),
            SizedBox(height: AppSpacingTokens.s16),
            if (state.others.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacingTokens.s16),
                child: Text(context.l10n.devicesEmpty, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              )
            else
              AppSettingsGroupWidget(
                children: [for (final device in state.others) _DeviceRow(device: device, onRevoke: () => _confirmRevoke(device))],
              ),
            SizedBox(height: AppSpacingTokens.s16),
            FilledButton(onPressed: () => _bloc.add(const DevicesEvent.inviteRequested()), child: Text(context.l10n.devicesAdd)),
          ],
        );
      },
    );
  }

  Future<void> _confirmRevoke(DeviceModel device) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.devicesRevokeTitle),
        // Revoking the device in your hand is a logout, and it reads
        // differently from cutting off a tablet you no longer have.
        content: Text(device.isCurrent ? l10n.devicesRevokeSelfMessage : l10n.devicesRevokeMessage),
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
    return ListTile(
      // Platform plus two moments, never the key: 32 bytes of base64 look
      // identical across five rows, and a person has to recognise their own.
      title: Text(device.isCurrent ? '${_platformName(device.platform)} · ${l10n.devicesCurrent}' : _platformName(device.platform)),
      subtitle: Text(
        '${l10n.devicesPairedAt(DateFormatter.short(device.pairedAt))} · ${l10n.devicesLastSeen(DateFormatter.short(device.lastSeenAt))}',
      ),
      trailing: TextButton(onPressed: onRevoke, child: Text(l10n.devicesRevoke)),
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

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.link, required this.onDismiss});

  final String link;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(AppSpacingTokens.s16),
        child: Column(
          children: [
            AppQrSurfaceWidget(data: link),
            SizedBox(height: AppSpacingTokens.s12),
            Text(context.l10n.devicesInviteMessage, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            SizedBox(height: AppSpacingTokens.s8),
            // Copying matters as much as the QR: Windows and Linux have no
            // camera, so text is the only path that works everywhere.
            SelectableText(link, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            // "Hide", not "Cancel": nothing here cancels the invite. The token
            // stays usable for its ten minutes whatever this button says, and
            // calling it Cancel would promise a revocation that does not happen.
            TextButton(onPressed: onDismiss, child: Text(context.l10n.actionHide)),
          ],
        ),
      ),
    );
  }
}
