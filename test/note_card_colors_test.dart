import 'package:app_smarana/features/notes/models/note_workspace_models.dart';
import 'package:app_smarana/features/notes/theme/note_card_colors.dart';
import 'package:app_smarana/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exposes exactly the eight requested note card colors', () {
    expect(selectableNoteCardColors, [
      NoteCardColor.yellow,
      NoteCardColor.blue,
      NoteCardColor.green,
      NoteCardColor.pink,
      NoteCardColor.purple,
      NoteCardColor.orange,
      NoteCardColor.teal,
      NoteCardColor.lavender,
    ]);
  });

  test('uses the opaque light and dark note-specific palette variants', () {
    const expectedLight = [
      Color(0xFFFFF8D6),
      Color(0xFFE3F2FD),
      Color(0xFFE6F4EA),
      Color(0xFFFCE8E6),
      Color(0xFFF3E8FD),
      Color(0xFFFEEED8),
      Color(0xFFE0F2F1),
      Color(0xFFE8EAF6),
    ];
    const expectedDark = [
      Color(0xFF4A4224),
      Color(0xFF263F52),
      Color(0xFF294334),
      Color(0xFF4A3030),
      Color(0xFF3E304D),
      Color(0xFF4A3825),
      Color(0xFF264442),
      Color(0xFF30334D),
    ];

    for (var index = 0; index < selectableNoteCardColors.length; index++) {
      final color = selectableNoteCardColors[index];
      final lightSurface = noteCardSurfaceColor(lightTheme, color);
      final darkSurface = noteCardSurfaceColor(darkTheme, color);

      expect(lightSurface, expectedLight[index]);
      expect(darkSurface, expectedDark[index]);
      expect(lightSurface.a, 1);
      expect(darkSurface.a, 1);
      expect(
        _contrastRatio(
          lightSurface,
          noteCardForegroundColor(lightTheme, color),
        ),
        greaterThanOrEqualTo(4.5),
        reason: '${color.name} must remain readable in light mode.',
      );
      expect(
        _contrastRatio(darkSurface, noteCardForegroundColor(darkTheme, color)),
        greaterThanOrEqualTo(4.5),
        reason: '${color.name} must remain readable in dark mode.',
      );
    }
  });

  test(
    'legacy saved colors resolve to the nearest current note palette color',
    () {
      expect(
        noteCardSurfaceColor(lightTheme, NoteCardColor.cyan),
        lightNoteCardPalette.noteTeal,
      );
      expect(
        noteCardSurfaceColor(lightTheme, NoteCardColor.sky),
        lightNoteCardPalette.noteBlue,
      );
      expect(
        noteCardSurfaceColor(lightTheme, NoteCardColor.mint),
        lightNoteCardPalette.noteGreen,
      );
    },
  );

  test('custom note text colors remain readable on every note surface', () {
    for (final theme in [lightTheme, darkTheme]) {
      for (final background in selectableNoteCardColors) {
        final surface = noteCardSurfaceColor(theme, background);
        for (final textColor in NoteTextColor.values) {
          expect(
            _contrastRatio(
              surface,
              noteCardForegroundColor(theme, background, textColor),
            ),
            greaterThanOrEqualTo(4.5),
            reason:
                '${textColor.name} must remain readable on '
                '${background.name} in ${theme.brightness}.',
          );
        }
      }
    }
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
