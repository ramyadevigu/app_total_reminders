import 'dart:async';

import 'package:app_smarana/features/auth/screens/login_screen.dart';
import 'package:app_smarana/features/auth/widgets/authentication_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('waits for auth state before showing signed-out login', (
    tester,
  ) async {
    final authStates = StreamController<bool>.broadcast();
    addTearDown(authStates.close);

    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticationGate(
          authenticationState: authStates.stream,
          authenticatedChild: const Text('Calendar'),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);

    authStates.add(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Calendar'), findsNothing);
    expect(find.text('Welcome to Total Reminders'), findsOneWidget);
  });

  testWidgets('shows the authenticated app after Firebase reports a session', (
    tester,
  ) async {
    final authStates = StreamController<bool>.broadcast();
    addTearDown(authStates.close);

    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticationGate(
          authenticationState: authStates.stream,
          authenticatedChild: const Text('Calendar'),
        ),
      ),
    );

    authStates.add(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Calendar'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('Google sign-in button prevents duplicate requests', (
    tester,
  ) async {
    final signInCompleter = Completer<void>();
    var signInCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onSignIn: () {
            signInCalls++;
            return signInCompleter.future;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    final button = find.byKey(const ValueKey('continue-with-google'));
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();

    expect(signInCalls, 1);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    signInCompleter.complete();
    await tester.pump();
    await tester.pump();

    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
  });

  testWidgets('a cancelled sign-in leaves the login screen without an error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(onSignIn: () async {})),
    );
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.byKey(const ValueKey('continue-with-google')));
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Welcome to Total Reminders'), findsOneWidget);
    expect(find.byKey(const ValueKey('login-error-message')), findsNothing);
  });

  testWidgets('login content remains scrollable on a compact display', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(onSignIn: () async {})),
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Total Reminders'), findsOneWidget);
    expect(find.byKey(const ValueKey('continue-with-google')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
