import 'package:flutter/material.dart';

enum MoveQuality {
  checkmate,
  brilliant,
  excellent,
  good,
  inaccuracy,
  mistake,
  blunder,
}

extension MoveQualityLabel on MoveQuality {
  String get label {
    switch (this) {
      case MoveQuality.checkmate:
        return 'Checkmate';
      case MoveQuality.brilliant:
        return 'Brilliant';
      case MoveQuality.excellent:
        return 'Excellent';
      case MoveQuality.good:
        return 'Good';
      case MoveQuality.inaccuracy:
        return 'Inaccuracy';
      case MoveQuality.mistake:
        return 'Mistake';
      case MoveQuality.blunder:
        return 'Blunder';
    }
  }

  Color get color {
    switch (this) {
      case MoveQuality.checkmate:
        return const Color(0xFFB78CFF);
      case MoveQuality.brilliant:
        return const Color(0xFF8B5CF6);
      case MoveQuality.excellent:
        return const Color(0xFF34D399);
      case MoveQuality.good:
        return const Color(0xFF6B7280);
      case MoveQuality.inaccuracy:
        return const Color(0xFFF59E0B);
      case MoveQuality.mistake:
        return const Color(0xFFF97316);
      case MoveQuality.blunder:
        return const Color(0xFFEF4444);
    }
  }

  String get icon {
    switch (this) {
      case MoveQuality.checkmate:
        return '#';
      case MoveQuality.brilliant:
        return '!!';
      case MoveQuality.excellent:
        return '!';
      case MoveQuality.good:
        return '';
      case MoveQuality.inaccuracy:
        return '?!';
      case MoveQuality.mistake:
        return '?';
      case MoveQuality.blunder:
        return '??';
    }
  }
}
