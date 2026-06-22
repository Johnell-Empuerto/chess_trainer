import 'package:chess_trainer/features/home/presentation/home_screen.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';

class Turn {
  final String displayName;
  final Color color;

  const Turn(this.displayName, this.color);

  static const white = Turn('White', Colors.white);
  static const black = Turn('Black', Colors.black);

  Turn get opposite => this == white ? black : white;
}

class ChessTrainerApp extends StatelessWidget {
  const ChessTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess Trainer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
