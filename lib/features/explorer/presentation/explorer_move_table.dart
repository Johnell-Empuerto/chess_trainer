import 'package:flutter/material.dart';

import 'package:chess_trainer/app/app_theme.dart';
import 'package:chess_trainer/features/engine/domain/engine_analysis_result.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_move_stat.dart';

class ExplorerMoveTable extends StatelessWidget {
  final List<ExplorerMoveStat> moves;
  final EngineAnalysisResult? engineResult;
  final ValueChanged<ExplorerMoveStat> onMoveSelected;

  const ExplorerMoveTable({
    super.key,
    required this.moves,
    required this.engineResult,
    required this.onMoveSelected,
  });

  @override
  Widget build(BuildContext context) {
    final showEvaluation = engineResult != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          _HeaderRow(showEvaluation: showEvaluation),
          const Divider(height: 1),
          for (final move in moves)
            _MoveRow(
              move: move,
              showEvaluation: showEvaluation,
              engineResult: engineResult,
              onTap: () => onMoveSelected(move),
            ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final bool showEvaluation;

  const _HeaderRow({required this.showEvaluation});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 54,
            child: _HeaderText('Move'),
          ),
          if (showEvaluation)
            const SizedBox(
              width: 54,
              child: _HeaderText('Eval'),
            ),
          const Expanded(
            flex: 2,
            child: _HeaderText('Games'),
          ),
          const Expanded(
            flex: 4,
            child: _HeaderText('Results'),
          ),
        ],
      ),
    );
  }
}

class _MoveRow extends StatelessWidget {
  final ExplorerMoveStat move;
  final bool showEvaluation;
  final EngineAnalysisResult? engineResult;
  final VoidCallback onTap;

  const _MoveRow({
    required this.move,
    required this.showEvaluation,
    required this.engineResult,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEngineMove = _isEngineMove(move, engineResult);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isEngineMove ? const Color(0x2234D399) : Colors.transparent,
          border: const Border(
            bottom: BorderSide(color: Color(0x22404040)),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 54,
              child: Text(
                move.moveSan,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isEngineMove
                      ? const Color(0xFF34D399)
                      : AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (showEvaluation)
              SizedBox(
                width: 54,
                child: Text(
                  isEngineMove ? _engineScore(engineResult) : '--',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isEngineMove
                        ? const Color(0xFF34D399)
                        : AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Expanded(
              flex: 2,
              child: Text(
                _compactCount(move.gamesCount),
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: _ResultBar(move: move),
            ),
          ],
        ),
      ),
    );
  }

  bool _isEngineMove(
    ExplorerMoveStat move,
    EngineAnalysisResult? engineResult,
  ) {
    final bestMove = engineResult?.bestMoveUci;
    if (bestMove == null || bestMove == 'none' || bestMove.length < 4) {
      return false;
    }

    return move.moveUci == bestMove || move.moveUci.startsWith(bestMove);
  }

  String _engineScore(EngineAnalysisResult? result) {
    if (result == null) return '--';
    final mateIn = result.mateIn;
    if (mateIn != null) {
      if (mateIn > 0) return 'M$mateIn';
      if (mateIn < 0) return '-M${mateIn.abs()}';
      return 'M0';
    }

    final evaluation = result.evaluationPawns;
    if (evaluation == null) return '--';

    final sign = evaluation > 0 ? '+' : '';
    return '$sign${evaluation.toStringAsFixed(2)}';
  }

  String _compactCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(count >= 10000000 ? 0 : 1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1)}k';
    }
    return '$count';
  }
}

class _ResultBar extends StatelessWidget {
  final ExplorerMoveStat move;

  const _ResultBar({required this.move});

  @override
  Widget build(BuildContext context) {
    final white = move.whiteWinRate;
    final draw = move.drawRate;
    final black = move.blackWinRate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                Expanded(
                  flex: _barFlex(white),
                  child: const ColoredBox(color: Color(0xFFEDE8DC)),
                ),
                Expanded(
                  flex: _barFlex(draw),
                  child: const ColoredBox(color: Color(0xFF7C838F)),
                ),
                Expanded(
                  flex: _barFlex(black),
                  child: const ColoredBox(color: Color(0xFF1A1A1A)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: _PercentText(white)),
            Expanded(child: _PercentText(draw)),
            Expanded(child: _PercentText(black)),
          ],
        ),
      ],
    );
  }

  int _barFlex(double rate) {
    return (rate * 1000).round().clamp(1, 1000);
  }
}

class _HeaderText extends StatelessWidget {
  final String text;

  const _HeaderText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: AppTheme.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _PercentText extends StatelessWidget {
  final double value;

  const _PercentText(this.value);

  @override
  Widget build(BuildContext context) {
    return Text(
      '${(value * 100).round()}%',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: AppTheme.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    );
  }
}
