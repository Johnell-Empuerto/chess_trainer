import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:chess_trainer/app/app_theme.dart';
import 'package:chess_trainer/features/import_game/data/pgn_import_service.dart';

class ImportGameDialogResult {
  final String pgnText;
  final bool requestComputerAnalysis;

  const ImportGameDialogResult({
    required this.pgnText,
    required this.requestComputerAnalysis,
  });
}

class ImportGameDialog extends StatefulWidget {
  const ImportGameDialog({super.key});

  @override
  State<ImportGameDialog> createState() => _ImportGameDialogState();
}

class _ImportGameDialogState extends State<ImportGameDialog> {
  final TextEditingController _pgnController = TextEditingController();
  final PgnImportService _importService = PgnImportService();
  bool _requestComputerAnalysis = false;
  bool _pickingFile = false;
  String? _error;

  @override
  void dispose() {
    _pgnController.dispose();
    super.dispose();
  }

  Future<void> _chooseFile() async {
    if (_pickingFile) return;

    setState(() {
      _pickingFile = true;
      _error = null;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pgn', 'txt'],
        allowMultiple: false,
        withData: true,
      );

      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        setState(() => _pickingFile = false);
        return;
      }

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        setState(() {
          _pickingFile = false;
          _error = 'Could not read the selected PGN file.';
        });
        return;
      }

      setState(() {
        _pgnController.text = utf8.decode(bytes, allowMalformed: true);
        _pickingFile = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pickingFile = false;
        _error = 'Could not choose PGN file: $error';
      });
    }
  }

  void _submit() {
    final pgnText = _pgnController.text.trim();
    if (pgnText.isEmpty) {
      setState(() => _error = 'Paste PGN text or choose a PGN file.');
      return;
    }

    try {
      final imported = _importService.parse(pgnText);
      if (imported.sanMoves.isEmpty) {
        setState(() => _error = 'No legal moves were found in this PGN.');
        return;
      }
    } on PgnImportException catch (error) {
      setState(() => _error = error.message);
      return;
    } catch (error) {
      setState(() => _error = 'PGN could not be loaded: $error');
      return;
    }

    Navigator.of(context).pop(
      ImportGameDialogResult(
        pgnText: pgnText,
        requestComputerAnalysis: _requestComputerAnalysis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import game'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 560,
          minWidth: 420,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _pgnController,
                minLines: 10,
                maxLines: 16,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Paste PGN text here',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickingFile ? null : _chooseFile,
                icon: _pickingFile
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file),
                label: Text(_pickingFile ? 'Choosing...' : 'Choose PGN File'),
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: _requestComputerAnalysis,
                onChanged: (value) {
                  setState(() {
                    _requestComputerAnalysis = value ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Request computer analysis'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Colors.redAccent.shade200,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.file_upload),
          label: const Text('Import Game'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(136, 44),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
