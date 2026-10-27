import 'package:flutter/material.dart';
import 'package:nox_app/general/constants.dart';

/// Opens a full-bleed viewer adaptively: a full-screen pushed [route] on a narrow
/// window, or a centred `Dialog` (over the current screen) on a wide one — the shape
/// the file view (5.3) and the image viewer (F4) share. [dialogChild] lazily builds
/// the in-dialog page (only on the wide path, so nothing is constructed on mobile).
/// [maxWidth] constrains the dialog body when set; [insetPadding] overrides the
/// `Dialog` inset when set — omit it to keep `Dialog`'s own default inset (passing
/// `null` to `Dialog` would instead collapse it to zero, so the two constructions
/// are kept distinct).
Future<void> showAdaptiveLightbox(
  BuildContext context, {
  required Widget Function() dialogChild,
  required Route<void> Function() route,
  EdgeInsets? insetPadding,
  double? maxWidth,
}) {
  final wide = MediaQuery.sizeOf(context).width >= Constants.railBreakpoint;
  if (!wide) return Navigator.of(context).push(route());

  Widget child = dialogChild();
  if (maxWidth != null) {
    child = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    );
  }
  final content = insetPadding == null
      ? Dialog(clipBehavior: Clip.antiAlias, child: child)
      : Dialog(insetPadding: insetPadding, clipBehavior: Clip.antiAlias, child: child);
  return showDialog<void>(context: context, builder: (_) => content);
}
