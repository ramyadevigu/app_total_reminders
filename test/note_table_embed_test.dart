import 'package:app_smarana/features/notes/screens/rich_note_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('edits table cells and adds rows and columns', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: RichNoteEditorScreen()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('note-editor-insert-button')),
    );
    await tester.tap(find.byKey(const ValueKey('note-editor-insert-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert table'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Add row'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(5));

    final headerCell = find.byType(TextField).at(1);
    await tester.showKeyboard(headerCell);
    await tester.enterText(headerCell, 'Updated header');
    tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Add row'),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!
        .call();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(7));

    tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Add column'),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!
        .call();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(10));
    expect(find.text('Updated header'), findsOneWidget);
  });
}
