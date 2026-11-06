import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_smarana/widgets/fade_indexed_stack.dart';

void main() {
  testWidgets('keeps every child mounted and only the active one hit-testable', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FadeIndexedStack(
          index: 1,
          children: [
            Text('first', key: const ValueKey('first')),
            GestureDetector(
              key: const ValueKey('second'),
              onTap: () => tapped++,
              child: const Text('second'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);

    await tester.tap(find.text('second'));
    expect(tapped, 1);

    final inactiveIgnore = tester.widget<IgnorePointer>(
      find.ancestor(
        of: find.text('first'),
        matching: find.byType(IgnorePointer),
      ).first,
    );
    expect(inactiveIgnore.ignoring, isTrue);
  });
}
