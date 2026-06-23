import 'package:flutter/material.dart';

import 'package:chess_trainer/app/app_theme.dart';
import 'package:chess_trainer/features/computer/domain/computer_level.dart';
import 'package:chess_trainer/features/computer/domain/computer_play_mode.dart';

class ComputerGameCard extends StatelessWidget {
  final ComputerPlayMode mode;
  final String? humanColor;
  final String? computerColor;
  final ComputerLevel level;
  final bool computerThinking;
  final bool canRequestHint;
  final String statusText;
  final String? error;
  final VoidCallback onStopGame;
  final VoidCallback onRequestHint;

  const ComputerGameCard({
    super.key,
    required this.mode,
    required this.humanColor,
    required this.computerColor,
    required this.level,
    required this.computerThinking,
    required this.canRequestHint,
    required this.statusText,
    required this.error,
    required this.onStopGame,
    required this.onRequestHint,
  });

  @override
  Widget build(BuildContext context) {
    final active = mode != ComputerPlayMode.off;

    if (!active) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                mode == ComputerPlayMode.gameOver
                    ? Icons.emoji_events
                    : Icons.smart_toy_outlined,
                size: 18,
                color: const Color(0xFF5BC0EB),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mode == ComputerPlayMode.gameOver
                      ? 'Computer Game Finished'
                      : 'Playing vs Computer',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (computerThinking)
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _ComputerDetailRow(
            label: 'You',
            value: _displayColor(humanColor),
          ),
          _ComputerDetailRow(
            label: 'Computer',
            value: _displayColor(computerColor),
          ),
          _ComputerDetailRow(
            label: 'Level',
            value: level.label,
          ),
          const SizedBox(height: 8),
          Text(
            statusText,
            style: TextStyle(
              color: error == null ? AppTheme.textSecondary : Colors.redAccent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(
              error!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onStopGame,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop Game'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: canRequestHint ? onRequestHint : null,
                  icon: const Icon(Icons.lightbulb_outline),
                  label: const Text('Hint'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _displayColor(String? color) {
    if (color == null || color.isEmpty) return '-';
    return '${color[0].toUpperCase()}${color.substring(1)}';
  }
}

class _ComputerDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _ComputerDetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
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
      ),
    );
  }
}
