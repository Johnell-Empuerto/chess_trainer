import 'dart:async';

import 'package:flutter/material.dart';

import 'package:chess_trainer/app/app_theme.dart';
import 'package:chess_trainer/core/chess/move.dart';
import 'package:chess_trainer/features/coach/data/ai_explainer_service.dart';
import 'package:chess_trainer/features/coach/data/stockfish_coach_service.dart';
import 'package:chess_trainer/features/coach/domain/coach_move_review.dart';
import 'package:chess_trainer/features/coach/domain/move_quality.dart';

class CoachPanel extends StatefulWidget {
  final MoveNode? moveNode;
  final StockfishCoachService coachService;
  final AiExplainerService? aiService;
  final String? openingName;

  const CoachPanel({
    super.key,
    required this.moveNode,
    required this.coachService,
    this.aiService,
    this.openingName,
  });

  @override
  State<CoachPanel> createState() => _CoachPanelState();
}

class _CoachPanelState extends State<CoachPanel> {
  CoachMoveReview? _review;
  bool _loading = false;
  String? _error;
  String? _aiExplanation;
  bool _generatingAi = false;

  @override
  void didUpdateWidget(CoachPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.moveNode?.id != oldWidget.moveNode?.id) {
      _review = null;
      _error = null;
      _aiExplanation = null;
      _loading = false;
      _generatingAi = false;
    }
  }

  Future<void> _analyze() async {
    final node = widget.moveNode;
    if (node == null || node.isRoot || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
      _aiExplanation = null;
    });

    try {
      final result = await widget.coachService.reviewMove(
        moveNode: node,
        openingName: widget.openingName,
      );

      if (!mounted) return;

      setState(() {
        _review = result;
        _loading = false;
        _error = result.hasError ? result.error : null;
      });

      if (!result.hasError) {
        unawaited(_autoGenerateAiExplanation(result));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _autoGenerateAiExplanation(CoachMoveReview review) async {
    final aiService = widget.aiService;
    if (!mounted || aiService == null || !aiService.isAvailable) return;

    setState(() => _generatingAi = true);

    try {
      final explanation = await aiService.generateExplanation(review);
      if (!mounted) return;
      setState(() {
        _aiExplanation = explanation;
        _generatingAi = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _generatingAi = false);
    }
  }

  Future<void> _regenerateAiExplanation() async {
    final review = _review;
    final aiService = widget.aiService;
    if (review == null || aiService == null || !aiService.isAvailable) return;

    setState(() => _generatingAi = true);

    try {
      final explanation = await aiService.generateExplanation(review);
      if (!mounted) return;
      setState(() {
        _aiExplanation = explanation;
        _generatingAi = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _generatingAi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.moveNode;

    if (node == null || node.isRoot) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'Select a move from the move tree to review.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AiStatusIndicator(aiService: widget.aiService),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(height: 10),
                Text(
                  'Analyzing with Stockfish\u2026',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          )
        else if (_error != null && _review == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent.shade200),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Colors.redAccent.shade200,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                _AnalyzeButton(onTap: _analyze),
              ],
            ),
          )
        else if (_review == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                Text(
                  'Review: ${node.san}',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _AnalyzeButton(onTap: _analyze),
              ],
            ),
          )
        else ...[
          _QualityBadge(quality: _review!.quality),
          const SizedBox(height: 12),
          _DetailRow(label: 'Move', value: _review!.playedSan),
          if (_review!.bestMoveUci.isNotEmpty)
            _DetailRow(label: 'Best move', value: _review!.bestMoveUci),
          if (_review!.evalBefore != null)
            _DetailRow(
              label: 'Eval before',
              value: _formatEval(_review!.evalBefore!),
            ),
          if (_review!.evalAfter != null)
            _DetailRow(
              label: 'Eval after',
              value: _formatEval(_review!.evalAfter!),
            ),
          if (_review!.evalLoss != null && _review!.evalLoss! > 0.01)
            _DetailRow(
              label: 'Eval loss',
              value: '${_review!.evalLoss!.toStringAsFixed(2)} pawns',
            ),
          if (_review!.pvLine.isNotEmpty)
            _DetailRow(
              label: 'PV',
              value: _review!.pvLine.take(6).join(' '),
            ),
          _DetailRow(label: 'Depth', value: '${_review!.depth}'),
          if (_review!.openingName != null && _review!.openingName!.isNotEmpty)
            _DetailRow(label: 'Opening', value: _review!.openingName!),
          const SizedBox(height: 12),
          _ExplanationBox(
            text: _aiExplanation ?? _review!.fallbackExplanation,
            isAiGenerated: _aiExplanation != null,
            generating: _generatingAi,
          ),
          if (widget.aiService != null && widget.aiService!.isAvailable) ...[
            const SizedBox(height: 8),
            _AiRegenerateButton(
              onTap: _regenerateAiExplanation,
              loading: _generatingAi,
            ),
          ],
        ],
      ],
    );
  }

  String _formatEval(double eval) {
    final sign = eval > 0 ? '+' : '';
    return '$sign${eval.toStringAsFixed(2)}';
  }
}

class _AiStatusIndicator extends StatelessWidget {
  final AiExplainerService? aiService;

  const _AiStatusIndicator({required this.aiService});

  @override
  Widget build(BuildContext context) {
    final status = aiService?.status ?? AiStatus.unavailable;

    final (IconData icon, Color color, String label) = switch (status) {
      AiStatus.running => (
          Icons.check_circle,
          const Color(0xFF22C55E),
          'Local AI: Running',
        ),
      AiStatus.initializing => (
          Icons.hourglass_top,
          const Color(0xFFF59E0B),
          'Local AI: Initializing\u2026',
        ),
      AiStatus.failed => (
          Icons.error_outline,
          const Color(0xFFEF4444),
          'Local AI: Failed, using template',
        ),
      AiStatus.unavailable => (
          Icons.info_outline,
          AppTheme.textSecondary,
          'Local AI: Not available',
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyzeButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AnalyzeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.analytics),
      label: const Text('Analyze This Move'),
    );
  }
}

class _QualityBadge extends StatelessWidget {
  final MoveQuality quality;

  const _QualityBadge({required this.quality});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: quality.color.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: quality.color.withAlpha(120)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            quality.icon,
            style: TextStyle(
              color: quality.color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            quality.label,
            style: TextStyle(
              color: quality.color,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
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

class _ExplanationBox extends StatelessWidget {
  final String text;
  final bool isAiGenerated;
  final bool generating;

  const _ExplanationBox({
    required this.text,
    required this.isAiGenerated,
    this.generating = false,
  });

  @override
  Widget build(BuildContext context) {
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
              if (generating)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else
                Icon(
                  isAiGenerated ? Icons.auto_awesome : Icons.info_outline,
                  size: 14,
                  color: isAiGenerated
                      ? const Color(0xFF8B5CF6)
                      : AppTheme.textSecondary,
                ),
              const SizedBox(width: 6),
              Text(
                generating
                    ? 'Generating AI explanation\u2026'
                    : isAiGenerated
                        ? 'AI Coach Explanation'
                        : 'Coach Note',
                style: TextStyle(
                  color: generating
                      ? const Color(0xFFF59E0B)
                      : isAiGenerated
                          ? const Color(0xFF8B5CF6)
                          : AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            generating ? '' : text,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiRegenerateButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool loading;

  const _AiRegenerateButton({
    required this.onTap,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: loading ? 0.6 : 1.0,
      child: OutlinedButton.icon(
        onPressed: loading ? null : onTap,
        icon: loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            : const Icon(Icons.auto_awesome, size: 16),
        label: const Text('Regenerate'),
      ),
    );
  }
}
