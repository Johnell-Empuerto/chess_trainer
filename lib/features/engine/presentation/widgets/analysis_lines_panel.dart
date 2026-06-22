import 'package:flutter/material.dart';

import 'package:chess_trainer/app/app_theme.dart';
import 'package:chess_trainer/features/engine/domain/engine_analysis_result.dart';

class AnalysisLinesPanel extends StatelessWidget {
  final EngineAnalysisResult? result;
  final bool isAnalyzing;

  const AnalysisLinesPanel({
    super.key,
    required this.result,
    required this.isAnalyzing,
  });

  @override
  Widget build(BuildContext context) {
    final lines = result?.lines.take(3).toList() ?? const [];

    if (lines.isEmpty) {
      return Text(
        isAnalyzing
            ? 'Waiting for live engine lines...'
            : 'No engine lines yet.',
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in lines)
          _AnalysisLineTile(
            line: line,
            isBestLine: line.multiPv == 1,
          ),
      ],
    );
  }
}

class _AnalysisLineTile extends StatelessWidget {
  final EngineAnalysisLine line;
  final bool isBestLine;

  const _AnalysisLineTile({
    required this.line,
    required this.isBestLine,
  });

  @override
  Widget build(BuildContext context) {
    final pv = line.principalVariation.join(' ');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: isBestLine ? const Color(0x2434D399) : const Color(0x18111111),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isBestLine ? const Color(0x6634D399) : AppTheme.divider,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '${line.multiPv}',
              style: TextStyle(
                color:
                    isBestLine ? const Color(0xFF34D399) : AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1C),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0x3334D399)),
            ),
            child: Text(
              _formatLineScore(line),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pv.isEmpty ? line.bestMoveUci ?? '...' : pv,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: isBestLine ? FontWeight.w700 : FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatLineScore(EngineAnalysisLine line) {
    final mateIn = line.mateIn;
    if (mateIn != null) {
      if (mateIn > 0) return 'M$mateIn';
      if (mateIn < 0) return '-M${mateIn.abs()}';
      return 'M0';
    }

    final evaluation = line.evaluationPawns;
    if (evaluation == null) return '--';

    final sign = evaluation > 0 ? '+' : '';
    return '$sign${evaluation.toStringAsFixed(2)}';
  }
}
