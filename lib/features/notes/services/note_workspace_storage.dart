import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/note_workspace_models.dart';
import '../theme/note_card_colors.dart';
import '../theme/notebook_colors.dart';

class NoteWorkspaceStorage {
  NoteWorkspaceStorage({SharedPreferences? preferences, this.saveString})
    : _providedPreferences = preferences;

  static const String _key = 'smarana_note_workspace_v1';
  static const int _schemaVersion = 4;
  Future<void> _operationQueue = Future<void>.value();
  bool _migrationRequired = false;
  bool _workspaceUnreadable = false;
  bool _workspaceValidated = false;
  bool _workspaceLoadFailed = false;

  final SharedPreferences? _providedPreferences;
  final Future<bool> Function(String key, String value)? saveString;

  Future<List<Notebook>> loadWorkspace() {
    return _runSerialized(() async {
      _workspaceLoadFailed = false;
      _workspaceValidated = false;
      try {
        final savedNotebooks = await _readWorkspace();
        final seededNotebooks = ensureQuickNotesNotebook(savedNotebooks);
        final notebooks = ensureDistinctNotebookColors(seededNotebooks);
        final savedNotebookColors = {
          for (final notebook in savedNotebooks)
            notebook.id: notebook.colorValue,
        };
        final savedNotebookNames = {
          for (final notebook in savedNotebooks) notebook.id: notebook.name,
        };
        final assignedNotebookColor = notebooks.any(
          (notebook) =>
              savedNotebookColors[notebook.id] != notebook.colorValue ||
              savedNotebookNames[notebook.id] != notebook.name,
        );
        final hasUncoloredNotes = notebooks.any(
          (notebook) => notebook.notes.any(
            (note) => note.color == NoteCardColor.standard,
          ),
        );

        final assignedNotes = [
          for (final notebook in notebooks)
            for (final note in notebook.notes)
              if (note.color != NoteCardColor.standard) note,
        ];
        final migrated = notebooks.map((notebook) {
          return notebook.copyWith(
            notes: notebook.notes.map((note) {
              if (note.color != NoteCardColor.standard) {
                return note;
              }
              final updated = note.copyWith(
                color: nextBalancedNoteColor(assignedNotes),
              );
              assignedNotes.add(updated);
              return updated;
            }).toList(),
          );
        }).toList();

        final tagColors = await _readTagColors();
        var assignedTagColor = false;
        for (final notebook in migrated) {
          for (final note in notebook.notes) {
            for (final tag in note.projectMetadata?.tags ?? const <String>[]) {
              final key = tag.trim().toLowerCase();
              if (key.isNotEmpty && !tagColors.containsKey(key)) {
                tagColors[key] = nextBalancedTagColor(tagColors.values);
                assignedTagColor = true;
              }
            }
          }
        }
        if (hasUncoloredNotes ||
            assignedTagColor ||
            assignedNotebookColor ||
            seededNotebooks.length != savedNotebooks.length ||
            _migrationRequired) {
          await _writeWorkspace(migrated, tagColors);
        }
        _workspaceValidated = true;
        return migrated;
      } finally {
        if (!_workspaceValidated) {
          _workspaceLoadFailed = true;
        }
      }
    });
  }

  Future<Map<String, NoteCardColor>> loadTagColors() {
    return _runSerialized(() async {
      await _readWorkspace();
      return _readTagColors();
    });
  }

  Future<void> saveWorkspace(
    List<Notebook> notebooks, {
    Map<String, NoteCardColor>? tagColors,
  }) {
    return _runSerialized(() async {
      if (_workspaceLoadFailed) {
        throw const FormatException(
          'The Notes workspace could not be loaded; reload it before saving.',
        );
      }
      if (!_workspaceValidated) {
        await _readWorkspace();
      }
      await _writeWorkspace(
        ensureQuickNotesNotebook(notebooks),
        tagColors ?? await _readTagColors(),
      );
    });
  }

  Future<List<Notebook>> _readWorkspace() async {
    _migrationRequired = false;
    _workspaceUnreadable = false;
    _workspaceValidated = false;
    final preferences =
        _providedPreferences ?? await SharedPreferences.getInstance();
    final raw = preferences.get(_key);
    if (raw == null) {
      return [];
    }
    if (raw is! String || raw.isEmpty) {
      _rejectUnreadableWorkspace();
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      _rejectUnreadableWorkspace();
    }
    if (decoded is! Map ||
        (decoded['version'] != 1 &&
            decoded['version'] != 2 &&
            decoded['version'] != 3 &&
            decoded['version'] != _schemaVersion) ||
        decoded['notebooks'] is! List) {
      _rejectUnreadableWorkspace();
    }
    _migrationRequired = decoded['version'] != _schemaVersion;
    if (decoded.containsKey('tagColors')) {
      final savedTagColors = decoded['tagColors'];
      if (savedTagColors is! Map) {
        _rejectUnreadableWorkspace();
      }
      for (final entry in savedTagColors.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String ||
            key.trim().isEmpty ||
            value is! String ||
            (noteCardColorFromName(value) == NoteCardColor.standard &&
                value != NoteCardColor.standard.name)) {
          _rejectUnreadableWorkspace();
        }
      }
    }

    final notebooks = <Notebook>[];
    final notebookIds = <String>{};
    for (final value in decoded['notebooks'] as List) {
      if (value is! Map) {
        _rejectUnreadableWorkspace();
      }
      final json = _stringKeyedMap(value);
      if (json['notes'] is! List ||
          (json['notes'] as List).any((note) => note is! Map)) {
        _rejectUnreadableWorkspace();
      }
      for (final noteValue in json['notes'] as List) {
        final noteJson = _stringKeyedMap(noteValue as Map);
        final attachments = noteJson['attachments'];
        if (attachments != null &&
            (attachments is! List ||
                attachments.any(
                  (attachment) =>
                      attachment is! Map || !_isValidAttachment(attachment),
                ))) {
          _rejectUnreadableWorkspace();
        }
        final metadataValue = noteJson['projectMetadata'];
        if (metadataValue != null && metadataValue is! Map) {
          _rejectUnreadableWorkspace();
        }
        if (metadataValue is Map) {
          final tags = _stringKeyedMap(metadataValue)['tags'];
          if (tags != null &&
              (tags is! List || tags.any((tag) => tag is! String))) {
            _rejectUnreadableWorkspace();
          }
        }
      }
      final colorValue = json['colorValue'];
      if (json['description'] is! String ||
          !json.containsKey('icon') ||
          colorValue is! int ||
          colorValue < 0 ||
          colorValue > 0xFFFFFFFF ||
          (colorValue & 0xFF000000) != 0xFF000000) {
        _migrationRequired = true;
      }
      final notebook = Notebook.fromJson(json);
      if (notebook.id.isEmpty || !notebookIds.add(notebook.id)) {
        _rejectUnreadableWorkspace();
      }
      final noteIds = <String>{};
      final notes = <NoteEntry>[];
      for (final note in notebook.notes) {
        if (note.id.isEmpty || !noteIds.add(note.id)) {
          _rejectUnreadableWorkspace();
        }
        if (note.notebookId != notebook.id) {
          _migrationRequired = true;
        }
        notes.add(note.copyWith(notebookId: notebook.id));
      }
      notebooks.add(notebook.copyWith(notes: notes));
    }
    return notebooks;
  }

  Never _rejectUnreadableWorkspace() {
    _workspaceUnreadable = true;
    throw const FormatException(
      'Saved Notes data is malformed or uses an unsupported version.',
    );
  }

  Future<Map<String, NoteCardColor>> _readTagColors() async {
    final preferences =
        _providedPreferences ?? await SharedPreferences.getInstance();
    final raw = preferences.get(_key);
    if (raw == null) {
      return {};
    }
    if (raw is! String || raw.isEmpty) {
      _rejectUnreadableWorkspace();
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      _rejectUnreadableWorkspace();
    }
    if (decoded is! Map ||
        (decoded['version'] != 1 &&
            decoded['version'] != 2 &&
            decoded['version'] != 3 &&
            decoded['version'] != _schemaVersion) ||
        decoded['notebooks'] is! List) {
      _rejectUnreadableWorkspace();
    }
    if (!decoded.containsKey('tagColors')) {
      return {};
    }
    if (decoded['tagColors'] is! Map) {
      _rejectUnreadableWorkspace();
    }
    final colors = <String, NoteCardColor>{};
    for (final entry in (decoded['tagColors'] as Map).entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String ||
          key.trim().isEmpty ||
          value is! String ||
          (noteCardColorFromName(value) == NoteCardColor.standard &&
              value != NoteCardColor.standard.name)) {
        _rejectUnreadableWorkspace();
      }
      final color = noteCardColorFromName(value);
      if (color != NoteCardColor.standard) {
        colors[key.trim().toLowerCase()] = color;
      }
    }
    return colors;
  }

  Future<void> _writeWorkspace(
    List<Notebook> notebooks,
    Map<String, NoteCardColor> tagColors,
  ) async {
    if (_workspaceUnreadable) {
      _rejectUnreadableWorkspace();
    }
    final preferences =
        _providedPreferences ?? await SharedPreferences.getInstance();
    final value = jsonEncode({
      'version': _schemaVersion,
      'notebooks': notebooks.map((notebook) => notebook.toJson()).toList(),
      'tagColors': {
        for (final entry in tagColors.entries)
          if (entry.key.trim().isNotEmpty)
            entry.key.trim().toLowerCase(): entry.value.name,
      },
    });
    final saved =
        await (saveString?.call(_key, value) ??
            preferences.setString(_key, value));
    if (!saved) {
      throw Exception('Unable to save the Notes workspace.');
    }
    _workspaceValidated = true;
  }

  Future<T> _runSerialized<T>(Future<T> Function() operation) {
    final result = _operationQueue.then((_) => operation());
    _operationQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}

bool _isValidAttachment(Map<dynamic, dynamic> value) {
  final json = _stringKeyedMap(value);
  final type = json['type'];
  final addedAt = json['addedAt'];
  return json['id'] is String &&
      json['name'] is String &&
      json['path'] is String &&
      type is String &&
      NoteAttachmentType.values.any(
        (attachmentType) => attachmentType.name == type,
      ) &&
      addedAt is String &&
      DateTime.tryParse(addedAt) != null;
}

Map<String, Object?> _stringKeyedMap(Map<dynamic, dynamic> value) => {
  for (final entry in value.entries)
    if (entry.key is String) entry.key as String: entry.value,
};
