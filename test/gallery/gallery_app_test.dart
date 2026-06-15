import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/gallery/gallery_app.dart';
import 'package:nox_app/gallery/gallery_page.dart';

void main() {
  testWidgets('GalleryApp builds and toggles theme', (tester) async {
    await tester.pumpWidget(const GalleryApp());
    // The gallery renders spinners (endless animation) → pump fixed frames, not settle.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(GalleryPage), findsOneWidget);

    // Toggle light → dark via the app-bar action; it should rebuild without error.
    await tester.tap(find.byTooltip('Toggle theme'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(GalleryPage), findsOneWidget);
  });
}
