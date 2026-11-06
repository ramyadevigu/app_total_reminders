import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileNameStore extends ChangeNotifier {
  ProfileNameStore({Future<SharedPreferences> Function()? getPreferences})
    : _getPreferences = getPreferences ?? SharedPreferences.getInstance;

  static final instance = ProfileNameStore();

  static const _keyPrefix = 'appProfileName_';

  final Future<SharedPreferences> Function() _getPreferences;
  final Map<String, String> _names = {};
  final Map<String, Future<void>> _loads = {};
  final Set<String> _loadedUserIds = {};

  String nameFor({required String userId, required String googleName}) {
    return _names[userId] ?? _fallbackName(googleName);
  }

  Future<void> load({
    required String userId,
    required String googleName,
  }) async {
    if (_loadedUserIds.contains(userId)) {
      return;
    }
    final pendingLoad = _loads[userId];
    if (pendingLoad != null) {
      await pendingLoad;
      return;
    }

    final load = _load(userId: userId, googleName: googleName);
    _loads[userId] = load;
    try {
      await load;
    } finally {
      _loads.remove(userId);
    }
  }

  Future<void> _load({
    required String userId,
    required String googleName,
  }) async {
    final preferences = await _getPreferences();
    final savedName = preferences.getString('$_keyPrefix$userId')?.trim();
    if (savedName?.isNotEmpty == true) {
      _names[userId] = savedName!;
    } else {
      final initialName = _fallbackName(googleName);
      _names[userId] = initialName;
      if (initialName != 'Google account') {
        final saved = await preferences.setString(
          '$_keyPrefix$userId',
          initialName,
        );
        if (!saved) {
          throw StateError('Unable to save the initial profile name.');
        }
      }
    }
    _loadedUserIds.add(userId);
    notifyListeners();
  }

  Future<void> save({
    required String userId,
    required String name,
    required String googleName,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Profile name cannot be empty.');
    }

    await load(userId: userId, googleName: googleName);
    final preferences = await _getPreferences();
    final saved = await preferences.setString(
      '$_keyPrefix$userId',
      trimmedName,
    );
    if (!saved) {
      throw StateError('Unable to save the profile name.');
    }
    _names[userId] = trimmedName;
    notifyListeners();
  }

  String _fallbackName(String googleName) {
    final trimmedName = googleName.trim();
    return trimmedName.isEmpty ? 'Google account' : trimmedName;
  }
}
