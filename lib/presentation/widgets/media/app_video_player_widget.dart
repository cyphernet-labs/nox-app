import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_opacity.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';
import 'package:video_player/video_player.dart';

/// Plays a video attachment from a file already on disk (5.3).
///
/// **From disk, never from the server.** A native player runs its own HTTP
/// stack - AVPlayer and ExoPlayer do not go through Dart's `HttpClient` - so a
/// streaming player would reach the server without passing the certificate pin
/// that feature 036 puts on both transports. It would also simply fail: the
/// server's certificate is self-signed and no platform trust store will accept
/// it. Handing the player a path that the pinned download already produced
/// keeps the one channel one channel.
///
/// The widget owns the controller's whole life. Three states, and the failing
/// one is not decoration: a file can arrive complete and still be unplayable
/// here (a codec the platform lacks), and that must read as "this file, not
/// this app" rather than as a blank rectangle.
class AppVideoPlayerWidget extends StatefulWidget {
  const AppVideoPlayerWidget({super.key, required this.localPath});

  final String localPath;

  @override
  State<AppVideoPlayerWidget> createState() => _AppVideoPlayerWidgetState();
}

class _AppVideoPlayerWidgetState extends State<AppVideoPlayerWidget> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialise();
  }

  /// Deliberately not fire-and-forget: an initialise that throws has to land in
  /// [_failed] rather than in the zone's unhandled-error handler, where the
  /// person would be left looking at a blank rectangle with nothing said.
  Future<void> _initialise() async {
    final controller = VideoPlayerController.file(File(widget.localPath));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on Object {
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggle() {
    final controller = _controller;
    if (controller == null) return;
    setState(() => controller.value.isPlaying ? controller.pause() : controller.play());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_failed) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacingTokens.s24),
        child: Text(
          context.l10n.videoPlaybackError,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacingTokens.s24),
        child: AppSpinnerWidget(size: AppDimensionTokens.icon.lg),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppDimensionTokens.radius.md),
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(controller),
                // The whole surface is the control. A play button that only
                // works inside its own 48dp is a worse target than the picture
                // it sits on, and the picture is doing nothing else.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    child: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: controller,
                      // Shown while paused and withdrawn while playing: a glyph
                      // parked over moving video is in the way of the thing the
                      // person came to watch.
                      builder: (context, value, _) =>
                          value.isPlaying ? const SizedBox.shrink() : Center(child: _PlayBadge(playing: value.isPlaying)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: AppSpacingTokens.s8),
        Row(
          children: [
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, _) => IconButton(
                tooltip: value.isPlaying ? context.l10n.videoPause : context.l10n.videoPlay,
                onPressed: _toggle,
                icon: AppIconWidget(
                  value.isPlaying ? NoxIcons.pauseFill : NoxIcons.playArrowFill,
                  size: AppDimensionTokens.icon.base,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            Expanded(
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: colorScheme.primary,
                  bufferedColor: colorScheme.onSurfaceVariant.withValues(alpha: NoxOpacity.ring),
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            SizedBox(width: AppSpacingTokens.s12),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, _) => Text(
                '${_clock(value.position)} / ${_clock(value.duration)}',
                // Digits that change every frame must not move the layout while
                // they do it.
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// `m:ss`, growing to `h:mm:ss` only when there is an hour to show.
  static String _clock(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours == 0) return '$minutes:$seconds';
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
}

/// The resting affordance over a paused video.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge({required this.playing});

  final bool playing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        // Its own ground, because it sits over a picture whose colours are not
        // ours to predict - on a pale frame a bare glyph disappears.
        color: colorScheme.scrim.withValues(alpha: NoxOpacity.scrim),
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: EdgeInsets.all(AppSpacingTokens.s12),
        child: AppIconWidget(
          playing ? NoxIcons.pauseFill : NoxIcons.playArrowFill,
          size: AppDimensionTokens.icon.lg,
          color: colorScheme.onPrimary,
        ),
      ),
    );
  }
}
