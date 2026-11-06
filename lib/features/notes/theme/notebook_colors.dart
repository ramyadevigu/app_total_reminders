import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../models/note_workspace_models.dart';

List<int> get notebookPaletteValues =>
    NotebookBaseColor.values.map((color) => color.value).toList();

int nextNotebookColorValue(Iterable<int> assignedValues) {
  final assigned = assignedValues.map(_opaqueColorValue).toSet();
  for (final color in NotebookBaseColor.values) {
    if (!assigned.contains(color.value)) {
      return color.value;
    }
  }

  var hue = (assigned.length * 137.508) % 360;
  for (var attempt = 0; attempt < 360; attempt++) {
    final color = HSLColor.fromAHSL(1, hue, 0.48, 0.74).toColor().toARGB32();
    if (!assigned.contains(color)) {
      return color;
    }
    hue = (hue + 17) % 360;
  }
  throw StateError('Unable to assign a unique notebook color.');
}

List<Notebook> ensureDistinctNotebookColors(Iterable<Notebook> notebooks) {
  final assignedColors = <int>{};
  return notebooks.map((notebook) {
    final colorValue = notebook.colorValue | 0xFF000000;
    if (assignedColors.add(colorValue)) {
      return notebook;
    }
    final distinctColor = nextNotebookColorValue(assignedColors);
    assignedColors.add(distinctColor);
    return notebook.copyWith(colorValue: distinctColor);
  }).toList();
}

Color notebookBaseColor(int colorValue) => Color(_opaqueColorValue(colorValue));

Color notebookSurfaceColor(ThemeData theme, int colorValue) {
  final base = HSLColor.fromColor(notebookBaseColor(colorValue));
  return base
      .withSaturation(base.saturation.clamp(0.42, 0.68).toDouble())
      .withLightness(theme.brightness == Brightness.light ? 0.86 : 0.24)
      .toColor();
}

Color notebookAccentColor(ThemeData theme, int colorValue) {
  final base = HSLColor.fromColor(notebookBaseColor(colorValue));
  return base
      .withSaturation(base.saturation.clamp(0.48, 0.72).toDouble())
      .withLightness(theme.brightness == Brightness.light ? 0.26 : 0.76)
      .toColor();
}

Color notebookForegroundColor(ThemeData theme, int colorValue) {
  return AppColors.highContrastForeground(
    notebookSurfaceColor(theme, colorValue),
  );
}

IconData notebookIconData(NotebookIcon? icon, NotebookIconType legacyType) {
  return switch (icon ?? defaultNotebookIcon(legacyType)) {
    NotebookIcon.folder => Icons.folder_outlined,
    NotebookIcon.book => Icons.book_outlined,
    NotebookIcon.notebook => Icons.library_books_outlined,
    NotebookIcon.autoStories => Icons.auto_stories_outlined,
    NotebookIcon.work => Icons.work_outline_rounded,
    NotebookIcon.flag => Icons.flag_outlined,
    NotebookIcon.heart => Icons.favorite_border_rounded,
    NotebookIcon.lightbulb => Icons.lightbulb_outline_rounded,
    NotebookIcon.school => Icons.school_outlined,
    NotebookIcon.science => Icons.science_outlined,
    NotebookIcon.palette => Icons.palette_outlined,
    NotebookIcon.travel => Icons.flight_takeoff_outlined,
    NotebookIcon.home => Icons.home_outlined,
    NotebookIcon.savings => Icons.savings_outlined,
    NotebookIcon.fitness => Icons.fitness_center_outlined,
    NotebookIcon.music => Icons.music_note_outlined,
    NotebookIcon.nature => Icons.nature_outlined,
    NotebookIcon.coffee => Icons.coffee_outlined,
    NotebookIcon.target => Icons.track_changes_outlined,
    NotebookIcon.shopping => Icons.shopping_bag_outlined,
  };
}

NotebookIcon defaultNotebookIcon(NotebookIconType type) {
  return switch (type) {
    NotebookIconType.work => NotebookIcon.work,
    NotebookIconType.goals => NotebookIcon.flag,
    NotebookIconType.journal => NotebookIcon.autoStories,
    NotebookIconType.health => NotebookIcon.heart,
    NotebookIconType.ideas => NotebookIcon.lightbulb,
    NotebookIconType.general => NotebookIcon.book,
  };
}

int _opaqueColorValue(int value) => value | 0xFF000000;
