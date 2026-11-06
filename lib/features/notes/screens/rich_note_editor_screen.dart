import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../theme/app_design_tokens.dart';
import '../../reminders/models/reminder.dart';
import '../../reminders/services/reminder_storage.dart';
import '../../../services/notification_service.dart';
import '../models/note_repeat_option.dart';
import '../models/note_workspace_models.dart';
import '../models/rich_note_draft.dart';
import '../services/note_attachment_storage.dart';
import '../services/note_editor_autosave_service.dart';
import '../theme/note_card_colors.dart';
import '../widgets/note_editor_action_sheets.dart';
import '../widgets/note_tag_chip.dart';
import '../widgets/note_table_embed_builder.dart';
import '../../../widgets/app_navigation_drawer.dart';

enum _FormattingColorTarget { highlight, text }

enum _NoteTemplate { meeting, project, daily }

class _NoteColorSelection {
  const _NoteColorSelection({required this.background, required this.text});

  final NoteCardColor background;
  final NoteTextColor text;
}

class _FormattingColorChoice {
  const _FormattingColorChoice(this.color, this.target);

  final Color color;
  final _FormattingColorTarget target;
}

class RichNoteEditorScreen extends StatefulWidget {
  const RichNoteEditorScreen({
    super.key,
    this.note,
    this.notebooks = const [],
    this.focusOnOpen = false,
    this.onAutosave,
    this.onDuplicate,
    this.onDelete,
    this.onPinChanged,
    this.onArchiveChanged,
    this.startWithChecklist = false,
    this.pickImageOnOpen = false,
    this.tagColors = const {},
    this.onTagColorsChanged,
    this.reminderStorage,
    this.navigationDrawer,
  });

  final NoteEntry? note;
  final List<Notebook> notebooks;
  final bool focusOnOpen;
  final Future<void> Function(RichNoteDraft draft)? onAutosave;
  final Future<void> Function(RichNoteDraft draft)? onDuplicate;
  final Future<void> Function(RichNoteDraft draft)? onDelete;
  final Future<void> Function(RichNoteDraft draft)? onPinChanged;
  final Future<void> Function(RichNoteDraft draft)? onArchiveChanged;
  final bool startWithChecklist;
  final bool pickImageOnOpen;
  final Map<String, NoteCardColor> tagColors;
  final Future<void> Function(Map<String, NoteCardColor> tagColors)?
  onTagColorsChanged;
  final ReminderStorage? reminderStorage;
  final Widget? navigationDrawer;

  @override
  State<RichNoteEditorScreen> createState() => _RichNoteEditorScreenState();
}

class _RichNoteEditorScreenState extends State<RichNoteEditorScreen> {
  final _titleController = TextEditingController();
  final _projectOwnerController = TextEditingController();
  final _projectTagsController = TextEditingController();
  final _autosaveService = NoteEditorAutosaveService();
  final _attachmentStorage = NoteAttachmentStorage();
  final _uuid = const Uuid();
  final _lastUpdated = ValueNotifier<DateTime?>(null);
  final _autosaveMessage = ValueNotifier<String>('');
  Future<void> _reminderSaveQueue = Future<void>.value();

  late final quill.QuillController _quillController;
  late final ReminderStorage _reminderStorage;
  late String _selectedNotebookId;
  late NoteCardColor _selectedNoteColor;
  late NoteTextColor _selectedNoteTextColor;
  late List<NoteAttachment> _attachments;
  late Map<String, NoteCardColor> _tagColors;
  bool _isExiting = false;
  late bool _isPinned;
  late bool _isArchived;
  bool _projectMetadataVisible = false;

  DateTime? _projectStartDate;
  DateTime? _projectEndDate;
  NoteProjectPriority? _projectPriority;
  NoteProjectStatus _projectStatus = NoteProjectStatus.toDo;
  String? _relatedCalendarEventId;
  List<Reminder> _availableCalendarReminders = const [];

  bool _reminderSectionVisible = false;
  bool _loadingReminder = false;
  String? _reminderId;
  bool _reminderEnabled = true;
  DateTime _reminderDateTime = DateTime.now().add(const Duration(minutes: 5));
  DateTime _reminderCreatedAt = DateTime.now();
  NoteRepeatOption _repeatOption = NoteRepeatOption.doesNotRepeat;
  String? _reminderSoundUri;
  String _reminderSoundName = 'Default';
  List<ReminderSoundOption> _availableAlarmSounds = const [];

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _titleController.text = note?.title ?? '';
    _isPinned = note?.isPinned ?? false;
    _isArchived = note?.isArchived ?? false;
    _selectedNotebookId =
        note?.notebookId ??
        (widget.notebooks.isEmpty
            ? defaultNotebookId
            : widget.notebooks.first.id);
    _selectedNoteColor = note?.color ?? NoteCardColor.yellow;
    _selectedNoteTextColor = note?.textColor ?? NoteTextColor.defaultText;
    _attachments = List<NoteAttachment>.of(note?.attachments ?? const []);
    _tagColors = Map<String, NoteCardColor>.of(widget.tagColors);
    final existingTags = note?.projectMetadata?.tags ?? const <String>[];
    if (_ensureTagColors(existingTags, persist: false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_persistTagColors());
        }
      });
    }
    _reminderStorage = widget.reminderStorage ?? ReminderStorage();
    final metadata = note?.projectMetadata;
    _projectMetadataVisible = metadata != null;
    _projectOwnerController.text = metadata?.owner ?? '';
    _projectTagsController.text = metadata?.tags.join(', ') ?? '';
    _projectStartDate = metadata?.startDate;
    _projectEndDate = metadata?.endDate;
    _projectPriority = metadata?.priority;
    _projectStatus = metadata?.status ?? NoteProjectStatus.toDo;
    _relatedCalendarEventId = metadata?.relatedCalendarEventId;

    _quillController = quill.QuillController(
      document: _buildDocument(note),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: false,
    );
    if (widget.startWithChecklist &&
        _quillController.document.toPlainText().trim().isEmpty) {
      _quillController.formatText(0, 1, quill.Attribute.unchecked);
    }

    _lastUpdated.value = note?.updatedAt ?? DateTime.now();

    _titleController.addListener(_queueAutosave);
    _quillController.addListener(_queueAutosave);

    final reminderId = note?.reminderId;
    if (reminderId != null && reminderId.isNotEmpty) {
      _reminderId = reminderId;
      _reminderSectionVisible = true;
      _loadingReminder = true;
      unawaited(_loadReminder(reminderId));
    }
    unawaited(_loadAvailableAlarmSounds());
    unawaited(_loadAvailableCalendarReminders());
    if (widget.pickImageOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_addImages());
        }
      });
    }
  }

  @override
  void dispose() {
    _titleController
      ..removeListener(_queueAutosave)
      ..dispose();
    _projectOwnerController.dispose();
    _projectTagsController.dispose();
    _quillController
      ..removeListener(_queueAutosave)
      ..dispose();
    _autosaveService.dispose();
    _lastUpdated.dispose();
    _autosaveMessage.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableCalendarReminders() async {
    try {
      final reminders = await _reminderStorage.getReminders();
      reminders.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      if (!mounted) {
        return;
      }
      setState(() {
        _availableCalendarReminders = reminders;
      });
    } on Exception {
      if (!mounted) {
        return;
      }
      setState(() {
        _availableCalendarReminders = const [];
      });
    }
  }

  Future<void> _loadAvailableAlarmSounds() async {
    final sounds = await NotificationService.instance.availableAlarmSounds();
    if (mounted) {
      setState(() {
        _availableAlarmSounds = sounds;
      });
    }
  }

  Future<void> _loadReminder(String reminderId) async {
    try {
      final reminders = await _reminderStorage.getReminders();
      final match = reminders.where((item) => item.id == reminderId);
      if (!mounted) {
        return;
      }
      if (match.isEmpty) {
        setState(() {
          _reminderId = null;
          _reminderSectionVisible = false;
          _loadingReminder = false;
        });
        return;
      }
      final reminder = match.first;
      setState(() {
        _reminderEnabled = reminder.enabled;
        _reminderDateTime = reminder.dateTime;
        _reminderCreatedAt = reminder.createdAt;
        _reminderSoundUri = reminder.soundUri;
        _reminderSoundName = reminder.soundName;
        _repeatOption = NoteRepeatOption.fromRecurrenceRule(
          reminder.recurrenceRule,
        );
        _loadingReminder = false;
      });
    } on Exception {
      if (mounted) {
        setState(() => _loadingReminder = false);
      }
    }
  }

  Future<void> _addReminder() async {
    _activateReminder();
    await _persistReminderQueued();
  }

  void _activateReminder() {
    setState(() {
      if (!_reminderSectionVisible) {
        _reminderCreatedAt = DateTime.now();
      }
      _reminderSectionVisible = true;
      _reminderEnabled = true;
    });
    _queueAutosave();
  }

  Future<void> _removeReminder() async {
    final reminderId = _reminderId;
    try {
      if (reminderId != null) {
        await _reminderStorage.deleteReminder(reminderId);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _reminderId = null;
        _reminderSectionVisible = false;
        _reminderEnabled = true;
        _repeatOption = NoteRepeatOption.doesNotRepeat;
      });
      _queueAutosave();
    } on Exception catch (error) {
      _showAttachmentError('Could not remove the reminder: $error');
    }
  }

  void _toggleReminderEnabled(bool value) {
    if (!_reminderSectionVisible && value) {
      unawaited(_addReminder());
      return;
    }
    setState(() => _reminderEnabled = value);
    unawaited(_persistReminderQueued());
  }

  Future<void> _pickReminderDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _reminderDateTime,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) {
      return;
    }
    setState(() {
      _reminderDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        _reminderDateTime.hour,
        _reminderDateTime.minute,
      );
    });
    if (!_reminderSectionVisible) {
      _activateReminder();
    }
    unawaited(_persistReminderQueued());
  }

  Future<void> _pickReminderTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_reminderDateTime),
    );
    if (time == null || !mounted) {
      return;
    }
    setState(() {
      _reminderDateTime = DateTime(
        _reminderDateTime.year,
        _reminderDateTime.month,
        _reminderDateTime.day,
        time.hour,
        time.minute,
      );
    });
    if (!_reminderSectionVisible) {
      _activateReminder();
    }
    unawaited(_persistReminderQueued());
  }

  void _selectRepeatOption(NoteRepeatOption option) {
    setState(() => _repeatOption = option);
    if (!_reminderSectionVisible) {
      _activateReminder();
    }
    unawaited(_persistReminderQueued());
  }

  Future<void> _selectReminderSound() async {
    final sounds = <ReminderSoundOption>[
      const ReminderSoundOption(name: 'Default', uri: null),
      ..._availableAlarmSounds,
    ];
    if (!sounds.any(
      (sound) =>
          sound.uri == _reminderSoundUri && sound.name == _reminderSoundName,
    )) {
      sounds.add(
        ReminderSoundOption(name: _reminderSoundName, uri: _reminderSoundUri),
      );
    }

    final selection = await showModalBottomSheet<ReminderSoundOption>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              'Alert sound',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final sound in sounds)
            ListTile(
              leading: Icon(
                _reminderSoundUri == sound.uri &&
                        _reminderSoundName == sound.name
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(sound.name),
              onTap: () => Navigator.of(context).pop(sound),
            ),
          if (_availableAlarmSounds.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text('No additional alarm sounds are available.'),
            ),
        ],
      ),
    );

    if (selection == null || !mounted) {
      return;
    }
    setState(() {
      _reminderSoundUri = selection.uri;
      _reminderSoundName = selection.name;
      if (!_reminderSectionVisible) {
        _reminderCreatedAt = DateTime.now();
      }
      _reminderSectionVisible = true;
    });
    unawaited(_persistReminderQueued());
  }

  Future<void> _persistReminderQueued() {
    final save = _reminderSaveQueue.then((_) => _persistReminder());
    _reminderSaveQueue = save.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return save;
  }

  Future<void> _persistReminder() async {
    final reminderId = _reminderId;
    if (reminderId == null && !_reminderSectionVisible) {
      return;
    }

    final title = _titleController.text.trim();
    final description = _quillController.document.toPlainText().trim();
    final reminder = Reminder(
      id: reminderId ?? _uuid.v4(),
      title: title.isEmpty ? 'Note reminder' : title,
      description: description.isEmpty
          ? null
          : description.length > 300
          ? description.substring(0, 300)
          : description,
      dateTime: _reminderDateTime,
      recurrenceRule: _repeatOption.toRecurrenceRule(_reminderDateTime),
      enabled: _reminderEnabled,
      soundUri: _reminderSoundUri,
      soundName: _reminderSoundName,
      createdAt: _reminderCreatedAt,
    );

    try {
      if (reminderId == null) {
        await _reminderStorage.addReminder(reminder);
        if (mounted) {
          setState(() => _reminderId = reminder.id);
        }
      } else {
        await _reminderStorage.updateReminder(reminder);
      }
    } on Exception catch (error) {
      if (mounted) {
        _showAttachmentError('Could not save the reminder: $error');
      }
    }
  }

  quill.Document _buildDocument(NoteEntry? note) {
    final rawDelta = note?.richContentDelta;
    if (rawDelta != null && rawDelta.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawDelta);
        if (decoded is List) {
          return quill.Document.fromJson(decoded.cast<Map<String, dynamic>>());
        }
      } on FormatException {
        // Fall back to plain text below.
      }
    }

    final doc = quill.Document();
    final content = note?.content.trim() ?? '';
    if (content.isNotEmpty) {
      doc.insert(0, '$content\n');
    }
    return doc;
  }

  RichNoteDraft _buildDraft() {
    final now = DateTime.now();
    final projectMetadata = _buildProjectMetadata();
    return RichNoteDraft(
      title: _titleController.text.trim(),
      richContentDelta: jsonEncode(
        _quillController.document.toDelta().toJson(),
      ),
      plainContent: _quillController.document.toPlainText().trim(),
      notebookId: _selectedNotebookId,
      attachments: List<NoteAttachment>.unmodifiable(_attachments),
      projectMetadata: projectMetadata,
      updatedAt: now,
      reminderId: _reminderId,
      color: _selectedNoteColor,
      textColor: _selectedNoteTextColor,
      isPinned: _isPinned,
      isArchived: _isArchived,
    );
  }

  NoteProjectMetadata? _buildProjectMetadata() {
    if (!_projectMetadataVisible) {
      return null;
    }
    final ownerText = _projectOwnerController.text.trim();
    final owner = ownerText.isEmpty ? null : ownerText;
    final tags = <String>[];
    final seen = <String>{};
    for (final raw in _projectTagsController.text.split(',')) {
      final tag = raw.trim();
      if (tag.isNotEmpty && seen.add(tag.toLowerCase())) {
        tags.add(tag);
      }
    }
    final metadata = NoteProjectMetadata(
      owner: owner,
      tags: tags,
      startDate: _projectStartDate,
      endDate: _projectEndDate,
      priority: _projectPriority,
      status: _projectStatus,
      relatedCalendarEventId: _relatedCalendarEventId,
    );
    return metadata.isEmpty ? null : metadata;
  }

  Future<void> _pickProjectStartDate() async {
    final initialDate = _projectStartDate ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) {
      return;
    }
    setState(() {
      _projectStartDate = date;
      final endDate = _projectEndDate;
      if (endDate != null && endDate.isBefore(date)) {
        _projectEndDate = date;
      }
    });
    _queueAutosave();
  }

  Future<void> _pickProjectEndDate() async {
    final initialDate = _projectEndDate ?? _projectStartDate ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) {
      return;
    }
    setState(() {
      _projectEndDate = date;
      final startDate = _projectStartDate;
      if (startDate != null && startDate.isAfter(date)) {
        _projectStartDate = date;
      }
    });
    _queueAutosave();
  }

  void _queueAutosave() {
    _autosaveMessage.value = 'Autosaving...';
    _autosaveService.queue(() async {
      await _performAutosave();
    });
  }

  Future<void> _performAutosave() async {
    try {
      final onAutosave = widget.onAutosave;
      final draft = _buildDraft();
      if (onAutosave != null) {
        await onAutosave(draft);
      }
      if (_reminderId != null) {
        await _persistReminderQueued();
      }
      if (!mounted) {
        return;
      }
      _lastUpdated.value = draft.updatedAt;
      _autosaveMessage.value = 'Saved';
    } on Exception {
      if (!mounted) {
        return;
      }
      _autosaveMessage.value = 'Autosave failed';
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Autosave failed. Your latest changes are still on screen.',
          ),
        ),
      );
    }
  }

  Future<void> _flushAutosave() async {
    await _autosaveService.flush(_performAutosave);
  }

  Future<void> _exitEditor() async {
    if (_isExiting) {
      return;
    }
    _isExiting = true;
    await _flushAutosave();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(_buildDraft());
  }

  Future<void> _addImages() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );
    if (picked == null || !mounted) {
      return;
    }

    final next = List<NoteAttachment>.of(_attachments);
    try {
      for (final file in picked.files) {
        final attachment = await _attachmentStorage.importFile(
          file: file,
          noteId: widget.note?.id ?? _uuid.v4(),
          type: NoteAttachmentType.image,
        );
        next.add(attachment);
      }
    } on Exception catch (error) {
      _showAttachmentError('Could not add image: $error');
    }

    setState(() {
      _attachments = next;
    });
    _queueAutosave();
  }

  Future<void> _addFiles() async {
    final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (picked == null || !mounted) {
      return;
    }

    final next = List<NoteAttachment>.of(_attachments);
    try {
      for (final file in picked.files) {
        final attachment = await _attachmentStorage.importFile(
          file: file,
          noteId: widget.note?.id ?? _uuid.v4(),
          type: NoteAttachmentType.file,
        );
        next.add(attachment);
      }
    } on Exception catch (error) {
      _showAttachmentError('Could not add file: $error');
    }

    setState(() {
      _attachments = next;
    });
    _queueAutosave();
  }

  Future<void> _insertHyperlink() async {
    final textController = TextEditingController();
    final urlController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Insert hyperlink'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                decoration: const InputDecoration(labelText: 'Text'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(labelText: 'URL'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Insert'),
            ),
          ],
        );
      },
    );

    if (result != true || !mounted) {
      return;
    }

    final text = textController.text.trim();
    final url = urlController.text.trim();
    if (text.isEmpty || url.isEmpty) {
      return;
    }

    final index = _quillController.selection.baseOffset.clamp(
      0,
      _quillController.document.length - 1,
    );
    _quillController.document.insert(index, '[$text]($url) ');
    _queueAutosave();
  }

  void _insertTableTemplate() {
    final index = _quillController.selection.baseOffset.clamp(
      0,
      _quillController.document.length - 1,
    );
    _quillController.replaceText(
      index,
      0,
      quill.BlockEmbed(
        NoteTableEmbedBuilder.embedType,
        NoteTableEmbedBuilder.defaultData,
      ),
      TextSelection.collapsed(offset: index + 1),
    );
    _queueAutosave();
  }

  Future<void> _openAttachment(NoteAttachment attachment) async {
    try {
      final opened = await _attachmentStorage.open(attachment);
      if (!opened && mounted) {
        _showAttachmentError('This attachment is missing from device storage.');
      }
    } on Exception catch (error) {
      _showAttachmentError('Could not open attachment: $error');
    }
  }

  Future<void> _removeAttachment(NoteAttachment attachment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('Remove attachment?'),
        content: Text('Remove "${attachment.name}" from this note?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await _attachmentStorage.remove(attachment);
      if (!mounted) {
        return;
      }
      setState(() {
        _attachments = _attachments
            .where((item) => item.id != attachment.id)
            .toList();
      });
      _queueAutosave();
    } on Exception catch (error) {
      _showAttachmentError('Could not remove attachment: $error');
    }
  }

  void _showAttachmentError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showReminderSettings() async {
    if (_loadingReminder) {
      return;
    }
    final colorScheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, refreshSheet) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.82,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 34,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Set Reminder',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close reminder settings',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  _buildReminderSection(() => refreshSheet(() {})),
                  const SizedBox(height: 14),
                  FilledButton(
                    key: const ValueKey('note-reminder-done-button'),
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReminderSection(VoidCallback refreshSheet) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final time = TimeOfDay.fromDateTime(_reminderDateTime);
    final isEnabled = _reminderSectionVisible && _reminderEnabled;

    return Column(
      key: const ValueKey('note-reminder-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          key: const ValueKey('note-reminder-enabled-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Set a reminder'),
          subtitle: const Text('Choose a date and time for this note.'),
          value: isEnabled,
          onChanged: (value) {
            _toggleReminderEnabled(value);
            refreshSheet();
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            'Date & Time',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _reminderDateTimeButton(
                context,
                key: const ValueKey('note-reminder-date-button'),
                icon: Icons.calendar_today_outlined,
                label: localizations.formatMediumDate(_reminderDateTime),
                onPressed: () async {
                  await _pickReminderDate();
                  refreshSheet();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _reminderDateTimeButton(
                context,
                key: const ValueKey('note-reminder-time-button'),
                icon: Icons.access_time_outlined,
                label: localizations.formatTimeOfDay(time),
                onPressed: () async {
                  await _pickReminderTime();
                  refreshSheet();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Row(
              children: [
                Icon(
                  Icons.repeat_rounded,
                  size: 19,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                const Text('Repeat'),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<NoteRepeatOption>(
                    key: const ValueKey('note-reminder-repeat-dropdown'),
                    value: _repeatOption,
                    isDense: true,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    borderRadius: BorderRadius.circular(14),
                    items: NoteRepeatOption.values
                        .map(
                          (option) => DropdownMenuItem<NoteRepeatOption>(
                            value: option,
                            child: Text(
                              option.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _selectRepeatOption(value);
                        refreshSheet();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.volume_up_outlined),
          title: const Text('Alert sound'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _reminderSoundName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          onTap: () async {
            await _selectReminderSound();
            refreshSheet();
          },
        ),
        SwitchListTile.adaptive(
          key: const ValueKey('note-project-mode-switch'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.lightbulb_outline_rounded),
          title: const Text('Project Mode'),
          subtitle: const Text(
            'Add due date, status, priority and project tags.',
          ),
          value: _projectMetadataVisible,
          onChanged: (value) {
            setState(() {
              _projectMetadataVisible = value;
            });
            _queueAutosave();
            refreshSheet();
          },
        ),
        if (_projectMetadataVisible)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('note-project-details-button'),
              onPressed: _showProjectDetails,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Project details'),
            ),
          ),
        if (_reminderSectionVisible)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('note-remove-reminder-button'),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    icon: const Icon(Icons.delete_outline),
                    title: const Text('Remove reminder?'),
                    content: const Text(
                      'This removes the reminder schedule linked to this note.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await _removeReminder();
                  refreshSheet();
                }
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove reminder'),
            ),
          ),
      ],
    );
  }

  Widget _reminderDateTimeButton(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        key: key,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 17, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleInlineAttribute(quill.Attribute attribute) {
    _quillController.formatSelection(attribute);
    _queueAutosave();
  }

  Future<void> _showTagsDialog() async {
    final controller = TextEditingController(text: _projectTagsController.text);
    final tags = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add tags'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Ideas, Campaigns, Work',
            helperText: 'Separate tags with commas.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (tags == null || !mounted) {
      return;
    }
    setState(() {
      _projectTagsController.text = tags;
      _projectMetadataVisible = true;
    });
    _ensureTagColors(_readTags(tags));
    _queueAutosave();
  }

  List<String> _readTags(String value) {
    final seen = <String>{};
    return [
      for (final raw in value.split(','))
        if (raw.trim().isNotEmpty && seen.add(raw.trim().toLowerCase()))
          raw.trim(),
    ];
  }

  String _tagKey(String tag) => tag.trim().toLowerCase();

  bool _ensureTagColors(Iterable<String> tags, {bool persist = true}) {
    final updated = Map<String, NoteCardColor>.of(_tagColors);
    var changed = false;
    for (final tag in tags) {
      final key = _tagKey(tag);
      if (key.isNotEmpty && !updated.containsKey(key)) {
        updated[key] = nextBalancedTagColor(updated.values);
        changed = true;
      }
    }
    if (!changed) {
      return false;
    }
    setState(() {
      _tagColors = updated;
    });
    if (persist) {
      unawaited(_persistTagColors());
    }
    return true;
  }

  Future<void> _persistTagColors() async {
    await widget.onTagColorsChanged?.call(
      Map<String, NoteCardColor>.unmodifiable(_tagColors),
    );
  }

  Future<void> _showTagColorPicker(String tag) async {
    final key = _tagKey(tag);
    final selectedColor = await showNoteTagColorPicker(
      context,
      current: _tagColors[key] ?? selectableNoteCardColors.first,
    );
    if (selectedColor == null || !mounted) {
      return;
    }
    setState(() {
      _tagColors[key] = selectedColor;
    });
    await _persistTagColors();
  }

  Widget _buildColorSwatch(
    BuildContext context, {
    required NoteCardColor color,
    required bool selected,
    required String tooltip,
    String? semanticLabel,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${semanticLabel ?? tooltip}${selected ? ', selected' : ''}',
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          key: ValueKey('note-color-${color.name}'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.resolve(context, AppMotion.micro),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: noteCardSwatchColor(theme, color),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: selected
                ? Icon(
                    Icons.check_rounded,
                    size: 19,
                    color: noteCardAccentColor(theme, color),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Future<void> _showAttachmentOptions() async {
    final option = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Add image'),
              onTap: () => Navigator.of(context).pop('image'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_rounded),
              title: const Text('Add file'),
              onTap: () => Navigator.of(context).pop('file'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (option == 'image') {
      await _addImages();
    } else if (option == 'file') {
      await _addFiles();
    }
  }

  Future<void> _duplicateCurrentNote() async {
    final onDuplicate = widget.onDuplicate;
    if (onDuplicate == null) {
      _showAttachmentError('Duplicate is unavailable from this screen.');
      return;
    }
    try {
      await _flushAutosave();
      await onDuplicate(_buildDraft());
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Note duplicated.')));
      }
    } on Exception catch (error) {
      _showAttachmentError('Could not duplicate note: $error');
    }
  }

  Future<void> _shareNote() async {
    final content = _quillController.document.toPlainText().trim();
    final title = _titleController.text.trim();
    final text = content.isEmpty ? title : '$title\n\n$content';
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } on Exception catch (error) {
      _showAttachmentError('Could not share note: $error');
    }
  }

  Future<void> _deleteCurrentNote() async {
    final onDelete = widget.onDelete;
    if (onDelete == null) {
      _showAttachmentError('Delete is unavailable from this screen.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('Delete note?'),
        content: Text(
          'Delete "${_titleController.text.trim().isEmpty ? 'Untitled' : _titleController.text.trim()}"? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await _flushAutosave();
      await onDelete(_buildDraft());
      if (mounted) {
        _isExiting = true;
        Navigator.of(context).pop();
      }
    } on Exception catch (error) {
      _showAttachmentError('Could not delete note: $error');
    }
  }

  Future<void> _showMoreOptions() async {
    final action = await NoteEditorMoreSheet.show(
      context,
      editedAt: _lastUpdated.value ?? widget.note?.updatedAt ?? DateTime.now(),
    );
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case NoteEditorMoreAction.findInNote:
        await _showFindInNote();
        break;
      case NoteEditorMoreAction.delete:
        await _deleteCurrentNote();
        break;
      case NoteEditorMoreAction.makeCopy:
        await _duplicateCurrentNote();
        break;
      case NoteEditorMoreAction.send:
        await _shareNote();
        break;
      case NoteEditorMoreAction.collaborator:
        _showAttachmentError('Collaborators are not available yet.');
        break;
      case NoteEditorMoreAction.labels:
        await _showTagsDialog();
        break;
      case NoteEditorMoreAction.helpAndFeedback:
        _showAttachmentError('Help and feedback are not available here yet.');
        break;
    }
  }

  Future<void> _showFindInNote() async {
    final searchController = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Find in note'),
        content: TextField(
          controller: searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: 'Search this note'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(searchController.text),
            child: const Text('Find'),
          ),
        ],
      ),
    );
    searchController.dispose();
    if (!mounted || query == null || query.trim().isEmpty) {
      return;
    }
    final plainText = _quillController.document.toPlainText();
    final start = plainText.toLowerCase().indexOf(query.trim().toLowerCase());
    if (start < 0) {
      _showAttachmentError('No matches found.');
      return;
    }
    final end = start + query.trim().length;
    _quillController.updateSelection(
      TextSelection(baseOffset: start, extentOffset: end),
      quill.ChangeSource.local,
    );
    _showAttachmentError('Match found.');
  }

  Future<void> _togglePinned() async {
    final callback = widget.onPinChanged;
    if (callback == null) {
      _showAttachmentError('Pinning is unavailable from this screen.');
      return;
    }
    final previousValue = _isPinned;
    try {
      setState(() => _isPinned = !previousValue);
      await callback(_buildDraft());
      if (!mounted) {
        return;
      }
      _queueAutosave();
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _isPinned = previousValue);
      }
      _showAttachmentError('Could not update pin: $error');
    }
  }

  Future<void> _toggleArchived() async {
    try {
      final callback = widget.onArchiveChanged;
      if (callback == null) {
        _showAttachmentError('Archive is unavailable from this screen.');
        return;
      }
      final previousValue = _isArchived;
      setState(() => _isArchived = !previousValue);
      await callback(_buildDraft());
      if (!mounted) {
        return;
      }
      await _flushAutosave();
      if (mounted) {
        _isExiting = true;
        Navigator.of(context).pop(_buildDraft());
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _isArchived = !_isArchived);
      }
      _showAttachmentError('Could not update archive: $error');
    }
  }

  void _insertCurrentDate() {
    final selection = _quillController.selection;
    final date = MaterialLocalizations.of(context)
        .formatMediumDate(DateTime.now());
    _quillController.replaceText(
      selection.start,
      selection.end - selection.start,
      date,
      TextSelection.collapsed(offset: selection.start + date.length),
    );
    _queueAutosave();
  }

  Future<void> _showTemplatePicker() async {
    final template = await showModalBottomSheet<_NoteTemplate>(
      context: context,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                'Choose a template',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final item in _NoteTemplate.values)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(_templateLabel(item)),
                onTap: () => Navigator.of(context).pop(item),
              ),
          ],
        ),
      ),
    );
    if (template == null || !mounted) {
      return;
    }
    final selection = _quillController.selection;
    final text = _templateText(template);
    _quillController.replaceText(
      selection.start,
      selection.end - selection.start,
      text,
      TextSelection.collapsed(offset: selection.start + text.length),
    );
    _queueAutosave();
  }

  String _templateLabel(_NoteTemplate template) {
    return switch (template) {
      _NoteTemplate.meeting => 'Meeting notes',
      _NoteTemplate.project => 'Project brief',
      _NoteTemplate.daily => 'Daily journal',
    };
  }

  String _templateText(_NoteTemplate template) {
    return switch (template) {
      _NoteTemplate.meeting => 'Agenda\n\nNotes\n\nAction items\n',
      _NoteTemplate.project => 'Goals\n\nKey milestones\n\nNext steps\n',
      _NoteTemplate.daily => 'Today\n\nWhat went well\n\nTomorrow\n',
    };
  }

  Future<void> _showNoteColorPicker() async {
    final selection = await showModalBottomSheet<_NoteColorSelection>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Note Colors',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Text('Background', style: theme.textTheme.labelLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final noteColor in selectableNoteCardColors)
                    _buildColorSwatch(
                      context,
                      color: noteColor,
                      selected: _selectedNoteColor == noteColor,
                      tooltip: noteCardColorLabel(noteColor),
                      semanticLabel:
                          '${noteCardColorLabel(noteColor)} note color',
                      onTap: () => Navigator.of(context).pop(
                        _NoteColorSelection(
                          background: noteColor,
                          text: _selectedNoteTextColor,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Text color', style: theme.textTheme.labelLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final textColor in NoteTextColor.values)
                    _buildTextColorSwatch(
                      context,
                      color: textColor,
                      selected: _selectedNoteTextColor == textColor,
                      onTap: () => Navigator.of(context).pop(
                        _NoteColorSelection(
                          background: _selectedNoteColor,
                          text: textColor,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (selection == null || !mounted) {
      return;
    }
    setState(() {
      _selectedNoteColor = selection.background;
      _selectedNoteTextColor = selection.text;
    });
    _queueAutosave();
  }

  Widget _buildTextColorSwatch(
    BuildContext context, {
    required NoteTextColor color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final label = switch (color) {
      NoteTextColor.defaultText => 'Default',
      NoteTextColor.charcoal => 'Charcoal',
      NoteTextColor.blue => 'Blue',
      NoteTextColor.green => 'Green',
      NoteTextColor.red => 'Red',
      NoteTextColor.purple => 'Purple',
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '$label note text color${selected ? ', selected' : ''}',
      child: Tooltip(
        message: 'Text: $label',
        child: InkWell(
          key: ValueKey('note-text-color-${color.name}'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.resolve(context, AppMotion.micro),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surface,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.text_fields_rounded,
                size: 20,
                color: noteTextColorSwatch(theme, color),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showProjectDetails() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, refreshSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.94,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(
                'Project details',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              _buildProjectMetadataSection(
                onRefresh: () => refreshSheet(() {}),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showInsertSheet() async {
    final action = await NoteEditorInsertSheet.show(context);
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case NoteEditorInsertAction.takePhoto:
        _showAttachmentError('Camera capture is not available yet.');
        break;
      case NoteEditorInsertAction.addImage:
        await _addImages();
        break;
      case NoteEditorInsertAction.recording:
        _showAttachmentError('Audio recording is not available yet.');
        break;
      case NoteEditorInsertAction.drawing:
        _showAttachmentError('Drawing notes are not available yet.');
        break;
      case NoteEditorInsertAction.tickBoxes:
        _toggleInlineAttribute(quill.Attribute.unchecked);
        break;
      case NoteEditorInsertAction.table:
        _insertTableTemplate();
        break;
    }
  }

  Future<void> _showFormattingOptions() async {
    final option = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.title_rounded),
                title: const Text('Heading'),
                onTap: () => Navigator.of(context).pop('heading'),
              ),
              ListTile(
                leading: const Icon(Icons.format_underlined_rounded),
                title: const Text('Underline'),
                onTap: () => Navigator.of(context).pop('underline'),
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Text colors'),
                onTap: () => Navigator.of(context).pop('text_colors'),
              ),
              ListTile(
                leading: const Icon(Icons.format_list_numbered_rounded),
                title: const Text('Numbered list'),
                onTap: () => Navigator.of(context).pop('numbered_list'),
              ),
              ListTile(
                leading: const Icon(Icons.link_rounded),
                title: const Text('Insert hyperlink'),
                onTap: () => Navigator.of(context).pop('link'),
              ),
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('Insert table'),
                onTap: () => Navigator.of(context).pop('table'),
              ),
              ListTile(
                leading: const Icon(Icons.code_rounded),
                title: const Text('Code block'),
                onTap: () => Navigator.of(context).pop('code'),
              ),
              ListTile(
                leading: const Icon(Icons.horizontal_rule_rounded),
                title: const Text('Insert divider'),
                onTap: () => Navigator.of(context).pop('divider'),
              ),
              ListTile(
                leading: const Icon(Icons.attach_file_rounded),
                title: const Text('Add file'),
                onTap: () => Navigator.of(context).pop('attachment'),
              ),
              ListTile(
                leading: const Icon(Icons.undo_rounded),
                title: const Text('Undo'),
                onTap: () => Navigator.of(context).pop('undo'),
              ),
              ListTile(
                leading: const Icon(Icons.redo_rounded),
                title: const Text('Redo'),
                onTap: () => Navigator.of(context).pop('redo'),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Insert date'),
                onTap: () => Navigator.of(context).pop('date'),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Insert template'),
                onTap: () => Navigator.of(context).pop('template'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    switch (option) {
      case 'heading':
        _toggleInlineAttribute(quill.Attribute.h1);
        break;
      case 'underline':
        _toggleInlineAttribute(quill.Attribute.underline);
        break;
      case 'text_colors':
        await _showFormattingColorPicker();
        break;
      case 'numbered_list':
        _toggleInlineAttribute(quill.Attribute.ol);
        break;
      case 'link':
        await _insertHyperlink();
        break;
      case 'table':
        _insertTableTemplate();
        break;
      case 'code':
        _toggleInlineAttribute(quill.Attribute.codeBlock);
        break;
      case 'divider':
        _insertDivider();
        break;
      case 'highlight':
        await _showHighlightColors();
        break;
      case 'attachment':
        await _showAttachmentOptions();
        break;
      case 'undo':
        _quillController.undo();
        _queueAutosave();
        break;
      case 'redo':
        _quillController.redo();
        _queueAutosave();
        break;
      case 'date':
        _insertCurrentDate();
        break;
      case 'template':
        await _showTemplatePicker();
        break;
      default:
        return;
    }
  }

  Future<void> _showHighlightColors() async {
    await _showFormattingColorPicker();
  }

  Future<void> _showFormattingColorPicker() async {
    final selection = _quillController.selection;
    if (selection.isCollapsed) {
      _showAttachmentError('Select text before applying a color.');
      return;
    }

    final choice = await showModalBottomSheet<_FormattingColorChoice>(
      context: context,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Text Colors',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              _formattingColorGroup(
                context,
                title: 'Text highlight',
                target: _FormattingColorTarget.highlight,
              ),
              const SizedBox(height: 14),
              _formattingColorGroup(
                context,
                title: 'Text color',
                target: _FormattingColorTarget.text,
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) {
      return;
    }
    final maximumOffset = _quillController.document.length - 1;
    final start = selection.start.clamp(0, maximumOffset);
    final end = selection.end.clamp(start, maximumOffset);
    if (start == end) {
      _showAttachmentError('Select text before applying a color.');
      return;
    }
    _quillController.updateSelection(
      TextSelection(baseOffset: start, extentOffset: end),
      quill.ChangeSource.local,
    );
    final hex = choice.color
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
    final attribute = choice.target == _FormattingColorTarget.text
        ? quill.ColorAttribute('#$hex')
        : quill.BackgroundAttribute('#$hex');
    _toggleInlineAttribute(attribute);
  }

  Widget _formattingColorGroup(
    BuildContext context, {
    required String title,
    required _FormattingColorTarget target,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final noteColors = target == _FormattingColorTarget.highlight
        ? noteTextHighlightColors
        : selectableNoteTextColors;
    final colors = noteColors
        .map((noteColor) {
          final color = noteCardSwatchColor(theme, noteColor);
          if (target == _FormattingColorTarget.text) {
            final hsl = HSLColor.fromColor(color);
            return hsl
                .withSaturation(math.max(0.62, hsl.saturation))
                .withLightness(
                  theme.brightness == Brightness.light ? 0.22 : 0.88,
                )
                .toColor();
          }
          return theme.brightness == Brightness.dark
              ? Color.lerp(color, colorScheme.surface, 0.75)!
              : color;
        })
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (var index = 0; index < colors.length; index++)
              Tooltip(
                message: '$title ${noteCardColorLabel(noteColors[index])}',
                child: Semantics(
                  button: true,
                  label: '$title ${noteCardColorLabel(noteColors[index])}',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () =>
                        Navigator.of(context)
                            .pop(_FormattingColorChoice(colors[index], target)),
                    child: AnimatedContainer(
                      duration: AppMotion.resolve(context, AppMotion.micro),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors[index],
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _insertDivider() {
    final selection = _quillController.selection;
    final start = selection.start.clamp(
      0,
      _quillController.document.length - 1,
    );
    final end = selection.end.clamp(
      start,
      _quillController.document.length - 1,
    );
    const divider = '\n────────────\n';
    _quillController.replaceText(
      start,
      end - start,
      divider,
      TextSelection.collapsed(offset: start + divider.length),
    );
    _queueAutosave();
  }

  Widget _toolbarButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    Key? key,
  }) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        key: key,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Widget _buildFloatingToolbar() {
    return SizedBox(
      key: const ValueKey('rich-note-formatting-toolbar'),
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _toolbarButton(
              key: const ValueKey('note-editor-insert-button'),
              tooltip: 'Add to note',
              icon: Icons.add_box_outlined,
              onPressed: _showInsertSheet,
            ),
            _toolbarButton(
              key: const ValueKey('note-editor-customize-button'),
              tooltip: 'Customize note',
              icon: Icons.palette_outlined,
              onPressed: _showNoteColorPicker,
            ),
            _toolbarButton(
              key: const ValueKey('note-editor-format-button'),
              tooltip: 'Text formatting',
              icon: Icons.text_format_rounded,
              onPressed: _showFormattingOptions,
            ),
            const Spacer(),
            _toolbarButton(
              key: const ValueKey('note-editor-more-menu'),
              tooltip: 'More options',
              icon: Icons.more_vert_rounded,
              onPressed: _showMoreOptions,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteMetadata() {
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final tags = _projectTagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ValueListenableBuilder<String>(
              valueListenable: _autosaveMessage,
              builder: (context, value, _) {
                if (value.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 2),
            Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                for (var index = 0; index < tags.length; index++)
                  NoteTagChip(
                    label: tags[index],
                    color:
                        _tagColors[_tagKey(tags[index])] ??
                        selectableNoteCardColors[index %
                            selectableNoteCardColors.length],
                    onColorChange: () => _showTagColorPicker(tags[index]),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noteSurface = noteCardSurfaceColor(theme, _selectedNoteColor);
    final noteForeground = noteCardForegroundColor(
      theme,
      _selectedNoteColor,
      _selectedNoteTextColor,
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _exitEditor();
        }
      },
      child: Scaffold(
        drawer: widget.navigationDrawer,
        backgroundColor: noteSurface,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          leadingWidth: widget.navigationDrawer == null ? 48 : 104,
          toolbarHeight: 54,
          titleSpacing: 0,
          backgroundColor: noteSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: widget.navigationDrawer == null
              ? IconButton(
                  key: const ValueKey('note-editor-back'),
                  tooltip: 'Close editor',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _exitEditor,
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppNavigationMenuButton(),
                    IconButton(
                      key: const ValueKey('note-editor-back'),
                      tooltip: 'Close editor',
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: _exitEditor,
                    ),
                  ],
                ),
          title: TextField(
            key: const ValueKey('rich-note-title-field'),
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            maxLines: 1,
            decoration: InputDecoration(
              hintText: 'Untitled',
              hintStyle: TextStyle(
                color: noteForeground.withValues(alpha: 0.65),
              ),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: noteForeground,
            ),
          ),
          actions: [
            IconButton(
              key: const ValueKey('note-editor-pin-button'),
              tooltip: _isPinned ? 'Unpin note' : 'Pin note',
              onPressed: _togglePinned,
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: Icon(
                _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              ),
            ),
            IconButton(
              key: const ValueKey('note-editor-reminder-button'),
              tooltip: 'Set reminder',
              onPressed: _showReminderSettings,
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: Icon(
                _reminderSectionVisible && _reminderEnabled
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none_rounded,
              ),
            ),
            IconButton(
              key: const ValueKey('note-editor-archive-button'),
              tooltip: _isArchived ? 'Unarchive note' : 'Archive note',
              onPressed: _toggleArchived,
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: Icon(
                _isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),
              _buildNoteMetadata(),
              Expanded(
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: noteForeground),
                  child: quill.QuillEditor.basic(
                    key: const ValueKey('rich-note-content-editor'),
                    controller: _quillController,
                    config: quill.QuillEditorConfig(
                      autoFocus: widget.focusOnOpen,
                      placeholder: 'Note',
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                      embedBuilders: const [NoteTableEmbedBuilder()],
                    ),
                  ),
                ),
              ),
              if (_attachments.isNotEmpty) _buildAttachmentSection(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: _buildFloatingToolbar(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentSection() {
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: _attachments.map((attachment) {
            final isImage = attachment.type == NoteAttachmentType.image;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                label: Text(attachment.name),
                avatar: Icon(
                  isImage ? Icons.image_outlined : Icons.attach_file,
                  size: 16,
                ),
                onPressed: () => _openAttachment(attachment),
                onDeleted: () => _removeAttachment(attachment),
                visualDensity: VisualDensity.compact,
                side: BorderSide.none,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildProjectMetadataSection({required VoidCallback onRefresh}) {
    final localizations = MaterialLocalizations.of(context);
    final hasLinkedReminder = _availableCalendarReminders.any(
      (item) => item.id == _relatedCalendarEventId,
    );
    final selectedCalendarEventId = hasLinkedReminder
        ? _relatedCalendarEventId
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('note-project-owner-field'),
          controller: _projectOwnerController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Owner',
            prefixIcon: Icon(Icons.person_outline),
          ),
          onChanged: (_) => _queueAutosave(),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('note-project-tags-field'),
          controller: _projectTagsController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Tags',
            hintText: 'Design, Sprint 3',
            prefixIcon: Icon(Icons.sell_outlined),
          ),
          onChanged: (_) {
            _ensureTagColors(_readTags(_projectTagsController.text));
            _queueAutosave();
            onRefresh();
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('note-project-start-date-button'),
              onPressed: () async {
                await _pickProjectStartDate();
                onRefresh();
              },
              icon: const Icon(Icons.play_arrow_outlined, size: 18),
              label: Text(
                _projectStartDate == null
                    ? 'Start date'
                    : localizations.formatMediumDate(_projectStartDate!),
              ),
            ),
            if (_projectStartDate != null)
              IconButton(
                tooltip: 'Clear start date',
                onPressed: () {
                  setState(() {
                    _projectStartDate = null;
                  });
                  _queueAutosave();
                  onRefresh();
                },
                icon: const Icon(Icons.close),
              ),
            OutlinedButton.icon(
              key: const ValueKey('note-project-end-date-button'),
              onPressed: () async {
                await _pickProjectEndDate();
                onRefresh();
              },
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: Text(
                _projectEndDate == null
                    ? 'End date'
                    : localizations.formatMediumDate(_projectEndDate!),
              ),
            ),
            if (_projectEndDate != null)
              IconButton(
                tooltip: 'Clear end date',
                onPressed: () {
                  setState(() {
                    _projectEndDate = null;
                  });
                  _queueAutosave();
                  onRefresh();
                },
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<NoteProjectPriority?>(
          key: const ValueKey('note-project-priority-dropdown'),
          initialValue: _projectPriority,
          decoration: const InputDecoration(labelText: 'Priority'),
          items: const [
            DropdownMenuItem<NoteProjectPriority?>(
              value: null,
              child: Text('Not set'),
            ),
            DropdownMenuItem<NoteProjectPriority?>(
              value: NoteProjectPriority.low,
              child: Text('Low'),
            ),
            DropdownMenuItem<NoteProjectPriority?>(
              value: NoteProjectPriority.medium,
              child: Text('Medium'),
            ),
            DropdownMenuItem<NoteProjectPriority?>(
              value: NoteProjectPriority.high,
              child: Text('High'),
            ),
          ],
          onChanged: (value) {
            setState(() {
              _projectPriority = value;
            });
            _queueAutosave();
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<NoteProjectStatus>(
          key: const ValueKey('note-project-status-dropdown'),
          initialValue: _projectStatus,
          decoration: const InputDecoration(labelText: 'Status'),
          items: const [
            DropdownMenuItem<NoteProjectStatus>(
              value: NoteProjectStatus.toDo,
              child: Text('To Do'),
            ),
            DropdownMenuItem<NoteProjectStatus>(
              value: NoteProjectStatus.inProgress,
              child: Text('In Progress'),
            ),
            DropdownMenuItem<NoteProjectStatus>(
              value: NoteProjectStatus.done,
              child: Text('Done'),
            ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _projectStatus = value;
            });
            _queueAutosave();
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          key: const ValueKey('note-project-calendar-link-dropdown'),
          initialValue: selectedCalendarEventId,
          decoration: const InputDecoration(
            labelText: 'Related calendar event',
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Not linked'),
            ),
            ..._availableCalendarReminders.map((reminder) {
              final formatted = localizations.formatMediumDate(
                reminder.dateTime,
              );
              return DropdownMenuItem<String?>(
                value: reminder.id,
                child: Text('${reminder.title} ($formatted)'),
              );
            }),
          ],
          onChanged: (value) {
            setState(() {
              _relatedCalendarEventId = value;
            });
            _queueAutosave();
          },
        ),
      ],
    );
  }
}
