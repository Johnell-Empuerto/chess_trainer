import 'package:flutter/material.dart';

import 'package:chess_trainer/app/app_theme.dart';
import 'package:chess_trainer/features/board/presentation/board_screen.dart';

/// Landing screen of the Chess Trainer app.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 32,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: AppTheme.accent,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.extension,
                        size: 56,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Chess Trainer',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Improve your game, one move at a time.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 40),
                  _MenuCard(
                    icon: Icons.grid_on,
                    title: 'Play / Training Board',
                    subtitle: 'Free play with full legal-move support',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BoardScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _MenuCard(
                    icon: Icons.extension,
                    title: 'Puzzles',
                    subtitle: 'Coming in Phase 2',
                    enabled: false,
                    onTap: () {},
                  ),
                  const SizedBox(height: 12),
                  _MenuCard(
                    icon: Icons.psychology,
                    title: 'AI Coach',
                    subtitle: 'Coming in Phase 2',
                    enabled: false,
                    onTap: () {},
                  ),
                  const SizedBox(height: 12),
                  _MenuCard(
                    icon: Icons.history_edu,
                    title: 'Game Review',
                    subtitle: 'Coming in Phase 2',
                    enabled: false,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppTheme.card : const Color(0xFF191C27),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: enabled ? AppTheme.accent : const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: enabled ? Colors.white : AppTheme.textMuted,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color:
                            enabled ? AppTheme.textPrimary : AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: enabled ? AppTheme.textSecondary : AppTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
