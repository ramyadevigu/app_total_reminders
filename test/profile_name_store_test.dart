import 'package:app_smarana/features/auth/services/profile_name_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('initializes the application name from Google profile data', () async {
    final store = ProfileNameStore();

    expect(
      store.nameFor(userId: 'user-1', googleName: 'Google Name'),
      'Google Name',
    );

    await store.load(userId: 'user-1', googleName: 'Google Name');

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('appProfileName_user-1'), 'Google Name');
  });

  test('persists an edited name independently for each user', () async {
    final store = ProfileNameStore();
    await store.load(userId: 'user-1', googleName: 'Google Name');
    await store.save(
      userId: 'user-1',
      googleName: 'Google Name',
      name: '  App Name  ',
    );

    expect(
      store.nameFor(userId: 'user-1', googleName: 'Google Name'),
      'App Name',
    );
    expect(
      store.nameFor(userId: 'user-2', googleName: 'Another Google Name'),
      'Another Google Name',
    );

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('appProfileName_user-1'), 'App Name');

    final reopenedStore = ProfileNameStore();
    await reopenedStore.load(userId: 'user-1', googleName: 'Google Name');
    expect(
      reopenedStore.nameFor(userId: 'user-1', googleName: 'Google Name'),
      'App Name',
    );
  });

  test('rejects an empty application profile name', () async {
    final store = ProfileNameStore();

    await expectLater(
      store.save(userId: 'user-1', googleName: 'Google Name', name: '  '),
      throwsArgumentError,
    );
  });
}
