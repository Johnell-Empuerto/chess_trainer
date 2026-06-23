import 'package:flutter/material.dart';

class BoardArrow {
  final String fromSquare;
  final String toSquare;
  final Color color;

  const BoardArrow({
    required this.fromSquare,
    required this.toSquare,
    this.color = const Color(0xCC16A085),
  });

  bool matches(String from, String to) {
    return fromSquare == from && toSquare == to;
  }
}

class BoardCircle {
  final String square;
  final Color color;

  const BoardCircle({
    required this.square,
    this.color = const Color(0xCC16A085),
  });

  bool matches(String squareName) {
    return square == squareName;
  }
}

enum ReviewAnnotationType {
  blunder,
  mistake,
  inaccuracy,
  miss,
  good,
  brilliant,
  checkmate,
  suggestion,
}

extension ReviewAnnotationTypeStyle on ReviewAnnotationType {
  Color get color {
    switch (this) {
      case ReviewAnnotationType.blunder:
        return const Color(0xDCEF4444);
      case ReviewAnnotationType.mistake:
        return const Color(0xDCF97316);
      case ReviewAnnotationType.inaccuracy:
        return const Color(0xDCF59E0B);
      case ReviewAnnotationType.miss:
        return const Color(0xDC60A5FA);
      case ReviewAnnotationType.good:
        return const Color(0xDC34D399);
      case ReviewAnnotationType.brilliant:
        return const Color(0xDC8B5CF6);
      case ReviewAnnotationType.checkmate:
        return const Color(0xDCB78CFF);
      case ReviewAnnotationType.suggestion:
        return const Color(0xDC22C55E);
    }
  }
}

class ReviewArrow {
  final String fromSquare;
  final String toSquare;
  final ReviewAnnotationType type;
  final bool isSuggestion;

  const ReviewArrow({
    required this.fromSquare,
    required this.toSquare,
    required this.type,
    this.isSuggestion = false,
  });

  Color get color => type.color;
}

class ReviewBadge {
  final String square;
  final String label;
  final ReviewAnnotationType type;

  const ReviewBadge({
    required this.square,
    required this.label,
    required this.type,
  });

  Color get color => type.color;
}

class BoardReviewOverlay {
  final List<ReviewArrow> arrows;
  final List<ReviewBadge> badges;

  const BoardReviewOverlay({
    this.arrows = const [],
    this.badges = const [],
  });

  const BoardReviewOverlay.empty()
      : arrows = const [],
        badges = const [];

  bool get isEmpty => arrows.isEmpty && badges.isEmpty;
}
