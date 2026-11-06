import 'package:app_smarana/app/app.dart';
import 'package:app_smarana/features/notes/models/note_workspace_models.dart';
import 'package:app_smarana/features/notes/services/note_workspace_storage.dart';
import 'package:app_smarana/widgets/app_navigation_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CountingWorkspaceStorage extends NoteWorkspaceStorage {
  int loads = 0;

  @override
  Future<List<Notebook>> loadWorkspace() {
    loads++;
    return Future.value(const <Notebook>[]);
  }
}

void main() {
  testWidgets('My Day is drawer-only and the drawer covers the shell height', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.byKey(const ValueKey('nav-my-day')), findsNothing);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsOneWidget);
    expect(find.byKey(const ValueKey('navigation-myDay')), findsOneWidget);
    expect(
      tester.getSize(find.byType(Drawer)).height,
      greaterThanOrEqualTo(
        tester.view.physicalSize.height / tester.view.devicePixelRatio - 1,
      ),
    );
  });

  testWidgets('selecting My Day opens its workspace without changing tabs', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('navigation-myDay')));
    await tester.pumpAndSettle();

    expect(find.text('My Day'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.byKey(const ValueKey('nav-calendar')), findsOneWidget);
    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navigationBar.indicatorColor, Colors.transparent);
  });

  testWidgets('drawer header shows the app name, not Profile', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.text('Total Reminders'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('drawer reloads notebooks only when the workspace changes', (
    tester,
  ) async {
    final storage = _CountingWorkspaceStorage();
    final changes = ValueNotifier<int>(0);
    Widget drawer({Brightness brightness = Brightness.light}) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: AppNavigationDrawer(
          selectedDestination: AppNavigationDestination.calendar,
          onDestinationSelected: (_) {},
          onNotebookSelected: (_) {},
          onNoteSelected: (_, _) {},
          workspaceStorage: storage,
          workspaceChanges: changes,
        ),
      ),
    );

    await tester.pumpWidget(drawer());
    await tester.pumpAndSettle();
    expect(storage.loads, 1);

    await tester.pumpWidget(drawer(brightness: Brightness.dark));
    await tester.pumpAndSettle();
    expect(storage.loads, 1);

    changes.value++;
    await tester.pumpAndSettle();
    expect(storage.loads, 2);
  });
}
