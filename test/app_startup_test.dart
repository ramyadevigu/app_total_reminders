import 'package:app_smarana/app/app_startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('startup uses a neutral loading indicator without splash art', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: StartupLoadingScreen()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
