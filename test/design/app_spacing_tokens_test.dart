import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/general/constants.dart';

/// AppSpacingTokens._scale = ((1.w + 1.h) / 2).clamp(0.85, 1.2): each `sN` is its
/// design-px value times the mean width/height ScreenUtil factor, clamped so the UI
/// stays near design size on every platform. These tests pin the FlutterView (its
/// physicalSize/dpr — `setSurfaceSize` does NOT reach the MediaQuery ScreenUtil
/// reads, see test/utils/golden.dart) at three surfaces to lock the 1.0 design
/// point plus the 1.2 ceiling and 0.85 floor, and confirm s0/s999 stay unscaled.
void main() {
  // Pins the FlutterView to [logical] (dpr 1 -> physicalSize == logical) so
  // ScreenUtil resolves against it, pumps a ScreenUtilInit on Constants.designSize,
  // and runs [expectations] inside the builder — the only place `.w`/`.h` (and thus
  // the tokens) are valid. ScreenUtilInit resolves size synchronously on the first
  // frame (ensureScreenSize defaults false), so no pumpAndSettle is needed.
  Future<void> pumpAtSurface(WidgetTester tester, Size logical, void Function() expectations) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = logical;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: Constants.designSize,
        builder: (context, _) {
          expectations();
          return const SizedBox.shrink();
        },
      ),
    );
  }

  testWidgets('resolves the scale to 1.0 on the 360-wide design surface (s16 == 16)', (tester) async {
    await pumpAtSurface(tester, Constants.designSize, () {
      // 360/360 and 779/779 both yield 1.0, so the mean factor is exactly 1.0.
      expect(AppSpacingTokens.s16, closeTo(16, 1e-6), reason: 'design surface -> scale 1.0');
      expect(AppSpacingTokens.s8, closeTo(8, 1e-6));
      expect(AppSpacingTokens.s32, closeTo(32, 1e-6));
    });
  });

  testWidgets('clamps to the 1.2 ceiling on a wide 1280x800 desktop surface (s16 == 19.2)', (tester) async {
    await pumpAtSurface(tester, const Size(1280, 800), () {
      // mean((1280/360), (800/779)) = 2.29 -> clamped down to the 1.2 ceiling.
      expect(AppSpacingTokens.s16, closeTo(16 * 1.2, 1e-6), reason: 'wide surface -> mean factor clamped to 1.2');
      expect(AppSpacingTokens.s8, closeTo(8 * 1.2, 1e-6));
      expect(AppSpacingTokens.s32, closeTo(32 * 1.2, 1e-6));
    });
  });

  testWidgets('clamps to the 0.85 floor on a tiny surface (s16 == 13.6)', (tester) async {
    await pumpAtSurface(tester, const Size(200, 300), () {
      // mean((200/360), (300/779)) = 0.47 -> clamped up to the 0.85 floor.
      expect(AppSpacingTokens.s16, closeTo(16 * 0.85, 1e-6), reason: 'tiny surface -> mean factor clamped to 0.85');
      expect(AppSpacingTokens.s8, closeTo(8 * 0.85, 1e-6));
    });
  });

  testWidgets('keeps s0 at 0 and the s999 pill marker at 999 unscaled on any surface', (tester) async {
    await pumpAtSurface(tester, const Size(1280, 800), () {
      // s0 and s999 are returned unscaled, so the wide surface must not move them.
      expect(AppSpacingTokens.s0, 0);
      expect(AppSpacingTokens.s999, 999);
    });
  });
}
