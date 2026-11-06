import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

class NoteTableEmbedBuilder extends quill.EmbedBuilder {
  const NoteTableEmbedBuilder();

  static const embedType = 'smarana-table';
  static const defaultData = '[["Column 1","Column 2"],["Value","Value"]]';

  @override
  String get key => embedType;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    return _EditableNoteTable(
      key: ValueKey(embedContext.node.documentOffset),
      controller: embedContext.controller,
      node: embedContext.node,
    );
  }
}

class _EditableNoteTable extends StatefulWidget {
  const _EditableNoteTable({
    super.key,
    required this.controller,
    required this.node,
  });

  final quill.QuillController controller;
  final quill.Embed node;

  @override
  State<_EditableNoteTable> createState() => _EditableNoteTableState();
}

class _EditableNoteTableState extends State<_EditableNoteTable> {
  late List<List<String>> _rows;
  late List<List<TextEditingController>> _cellControllers;

  @override
  void initState() {
    super.initState();
    _rows = _decodeRows(widget.node.value.data);
    _cellControllers = _createControllers(_rows);
  }

  @override
  void didUpdateWidget(covariant _EditableNoteTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextRows = _decodeRows(widget.node.value.data);
    if (jsonEncode(nextRows) == jsonEncode(_rows)) {
      return;
    }
    _disposeControllers();
    setState(() {
      _rows = nextRows;
      _cellControllers = _createControllers(_rows);
    });
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTableActions(context),
          Table(
            border: TableBorder.all(color: colors.outlineVariant),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              for (var rowIndex = 0; rowIndex < _rows.length; rowIndex++)
                TableRow(
                  decoration: rowIndex == 0
                      ? BoxDecoration(color: colors.surfaceContainerHighest)
                      : null,
                  children: [
                    for (
                      var columnIndex = 0;
                      columnIndex < _rows[rowIndex].length;
                      columnIndex++
                    )
                      _buildCell(context, rowIndex, columnIndex),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          tooltip: 'Add row',
          onPressed: _addRow,
          icon: const Icon(Icons.add_box_outlined),
        ),
        IconButton(
          tooltip: 'Add column',
          onPressed: _addColumn,
          icon: const Icon(Icons.view_column_outlined),
        ),
        IconButton(
          tooltip: 'Remove row',
          onPressed: _rows.length > 1 ? _removeRow : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        IconButton(
          tooltip: 'Remove column',
          onPressed: _rows.first.length > 1 ? _removeColumn : null,
          icon: const Icon(Icons.view_column_outlined),
        ),
      ],
    );
  }

  Widget _buildCell(BuildContext context, int rowIndex, int columnIndex) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: TextField(
        controller: _cellControllers[rowIndex][columnIndex],
        minLines: 1,
        maxLines: 3,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        ),
        style: rowIndex == 0
            ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)
            : theme.textTheme.bodyMedium,
        onChanged: (value) {
          _rows[rowIndex][columnIndex] = value;
          _replaceTable();
        },
      ),
    );
  }

  void _addRow() {
    setState(() {
      _rows.add(List<String>.generate(_rows.first.length, (_) => ''));
      _cellControllers.add(_createControllers([_rows.last]).single);
    });
    _replaceTable();
  }

  void _addColumn() {
    setState(() {
      for (var rowIndex = 0; rowIndex < _rows.length; rowIndex++) {
        _rows[rowIndex].add('');
        _cellControllers[rowIndex].add(TextEditingController());
      }
    });
    _replaceTable();
  }

  void _removeRow() {
    if (_rows.length <= 1) {
      return;
    }
    setState(() {
      final controllers = _cellControllers.removeLast();
      for (final controller in controllers) {
        controller.dispose();
      }
      _rows.removeLast();
    });
    _replaceTable();
  }

  void _removeColumn() {
    if (_rows.first.length <= 1) {
      return;
    }
    setState(() {
      for (final controllers in _cellControllers) {
        controllers.removeLast().dispose();
      }
      for (final row in _rows) {
        row.removeLast();
      }
    });
    _replaceTable();
  }

  void _replaceTable() {
    final offset = widget.node.documentOffset;
    widget.controller.replaceText(
      offset,
      1,
      quill.BlockEmbed(NoteTableEmbedBuilder.embedType, jsonEncode(_rows)),
      null,
    );
  }

  List<List<TextEditingController>> _createControllers(
    List<List<String>> rows,
  ) {
    return [
      for (final row in rows)
        [for (final cell in row) TextEditingController(text: cell)],
    ];
  }

  void _disposeControllers() {
    for (final row in _cellControllers) {
      for (final controller in row) {
        controller.dispose();
      }
    }
  }
}

List<List<String>> _decodeRows(Object? data) {
  try {
    final decoded = jsonDecode(data as String);
    if (decoded is List && decoded.isNotEmpty) {
      final rows = decoded
          .whereType<List>()
          .map((row) => row.map((cell) => cell.toString()).toList())
          .where((row) => row.isNotEmpty)
          .toList();
      if (rows.isNotEmpty) {
        final columnCount = rows
            .map((row) => row.length)
            .reduce((left, right) => left > right ? left : right);
        return [
          for (final row in rows)
            [...row, ...List<String>.filled(columnCount - row.length, '')],
        ];
      }
    }
  } on FormatException {
    // Fall through to a safe table shape for older or corrupted notes.
  }
  return const [
    ['Column 1', 'Column 2'],
    ['Value', 'Value'],
  ];
}
