import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/theme/nox_brand.dart';

// US3 / FR-014: generated-avatar foundation is deterministic and matches
// design-system.md §2.5 (8-color palette, hash index, initials, forum fallback).
void main() {
  test('avatar index is deterministic and in range', () {
    expect(noxAvatarIndex('Alice'), noxAvatarIndex('Alice'));
    for (final name in ['Alice', 'Bob', 'User1234', 'Чат', '']) {
      final i = noxAvatarIndex(name);
      expect(i, inInclusiveRange(0, noxAvatarPalette.length - 1));
    }
  });

  test('avatar color is a palette member', () {
    expect(noxAvatarPalette.length, 8);
    expect(noxAvatarPalette, contains(noxAvatarColor('Alice')));
  });

  test('initials: two words / single word / fallback', () {
    expect(noxInitials('Alice Bob'), 'AB');
    expect(noxInitials('alice'), 'AL');
    expect(noxInitials('  '), isNull); // -> forum glyph fallback
    expect(noxInitials('🎉🎊'), isNull); // no alphanumerics -> fallback
  });
}
