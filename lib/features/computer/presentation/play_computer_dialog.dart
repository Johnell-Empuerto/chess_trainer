import 'package:flutter/material.dart';

import 'package:chess_trainer/app/app_theme.dart';
import 'package:chess_trainer/features/computer/domain/computer_level.dart';

class PlayComputerSettings {
  final String humanColor;
  final ComputerLevel level;

  const PlayComputerSettings({
    required this.humanColor,
    required this.level,
  });
}

class PlayComputerDialog extends StatefulWidget {
  final String sideToMove;
  final String? openingName;
  final String initialHumanColor;
  final ComputerLevel initialLevel;

  const PlayComputerDialog({
    super.key,
    required this.sideToMove,
    required this.openingName,
    required this.initialHumanColor,
    required this.initialLevel,
  });

  @override
  State<PlayComputerDialog> createState() => _PlayComputerDialogState();
}

class _PlayComputerDialogState extends State<PlayComputerDialog> {
  late String _humanColor;
  late ComputerLevel _level;

  @override
  void initState() {
    super.initState();
    _humanColor = widget.initialHumanColor;
    _level = widget.initialLevel;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Continue vs Computer'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PositionPreview(
              sideToMove: widget.sideToMove,
              openingName: widget.openingName,
            ),
            const SizedBox(height: 16),
            Text(
              'Choose side',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'white',
                  icon: Icon(Icons.circle_outlined),
                  label: Text('White'),
                ),
                ButtonSegment(
                  value: 'black',
                  icon: Icon(Icons.circle),
                  label: Text('Black'),
                ),
              ],
              selected: {_humanColor},
              onSelectionChanged: (selection) {
                setState(() {
                  _humanColor = selection.first;
                });
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Level',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ComputerLevel>(
              initialValue: _level,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final level in ComputerLevel.values)
                  DropdownMenuItem(
                    value: level,
                    child: Text(level.label),
                  ),
              ],
              onChanged: (level) {
                if (level == null) return;
                setState(() {
                  _level = level;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop(
              PlayComputerSettings(
                humanColor: _humanColor,
                level: _level,
              ),
            );
          },
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start'),
        ),
      ],
    );
  }
}

class _PositionPreview extends StatelessWidget {
  final String sideToMove;
  final String? openingName;

  const _PositionPreview({
    required this.sideToMove,
    required this.openingName,
  });

  @override
  Widget build(BuildContext context) {
    final opening = openingName;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PreviewRow(label: 'Side to move', value: sideToMove),
          if (opening != null && opening.isNotEmpty) ...[
            const SizedBox(height: 6),
            _PreviewRow(label: 'Opening', value: opening),
          ],
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;

  const _PreviewRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style.copyWith(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
