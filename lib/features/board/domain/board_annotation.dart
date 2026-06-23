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
