import 'package:app_smarana/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });
}
