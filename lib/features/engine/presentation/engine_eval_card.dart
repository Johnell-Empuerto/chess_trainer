import 'package:flutter/material.dart';

import 'package:chess_trainer/app/app_theme.dart';

/// Placeholder engine evaluation card.
///
/// Real Stockfish / engine evaluation will be added in Phase 2.
/// For Phase 1, this file must not import EngineService or EngineEval.
class EngineEvalCard extends StatelessWidget {
  final bool isThinking;

  const EngineEvalCard({
    super.key,
    this.isThinking = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.divider,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.memory,
            size: 18,
            color: AppTheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Engine evaluation will be added in Phase 2.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (isThinking)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primary,
              ),
            ),
        ],
      ),
    );
  }
}
