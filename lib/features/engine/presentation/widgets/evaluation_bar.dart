import 'package:flutter/material.dart';

import 'package:chess_trainer/app/app_theme.dart';

class EvaluationBar extends StatelessWidget {
  final double? evaluationPawns;
  final int? mateIn;
  final bool isAnalyzing;

  const EvaluationBar({
    super.key,
    required this.evaluationPawns,
    required this.mateIn,
    required this.isAnalyzing,
  });

  @override
  Widget build(BuildContext context) {
    final whiteShare = _whiteShare();
    final label = _scoreLabel();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFF3A3A3A)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 12,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: whiteShare),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, animatedWhiteShare, child) {
            return Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xFF151515)),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    widthFactor: 1,
                    heightFactor: animatedWhiteShare,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFFF7F2E8),
                            Color(0xFFE4D8C4),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 30,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xDD202020),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0x5534D399)),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      height: 1,
                      color: const Color(0x7734D399),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 8,
                  child: Text(
                    'B',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: Text(
                    'W',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (isAnalyzing)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 26,
                    child: _ThinkingPulse(),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  double _whiteShare() {
    final mateScore = mateIn;
    if (mateScore != null) {
      if (mateScore > 0) return 0.96;
      if (mateScore < 0) return 0.04;
    }

    final score = evaluationPawns;
    if (score == null) return 0.5;

    final clamped = score.clamp(-5.0, 5.0);
    return (0.5 + (clamped / 10.0)).clamp(0.05, 0.95);
  }

  String _scoreLabel() {
    final mateScore = mateIn;
    if (mateScore != null) {
      if (mateScore > 0) return 'M$mateScore';
      if (mateScore < 0) return '-M${mateScore.abs()}';
      return 'M0';
    }

    final score = evaluationPawns;
    if (score == null) return '--';

    final sign = score > 0 ? '+' : '';
    return '$sign${score.toStringAsFixed(2)}';
  }
}

class _ThinkingPulse extends StatefulWidget {
  @override
  State<_ThinkingPulse> createState() => _ThinkingPulseState();
}

class _ThinkingPulseState extends State<_ThinkingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFF34D399),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}
