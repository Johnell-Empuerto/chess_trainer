enum TrainingTheme {
  tactics,
  endgame,
  opening,
  kingSafety,
  centerControl,
  pieceDevelopment,
  materialAwareness,
  pawnStructure,
  prophylaxis,
  tempo,
  initiative,
  coordination;

  String get label {
    switch (this) {
      case TrainingTheme.tactics:
        return 'Tactical awareness';
      case TrainingTheme.endgame:
        return 'Endgame technique';
      case TrainingTheme.opening:
        return 'Opening principles';
      case TrainingTheme.kingSafety:
        return 'King safety';
      case TrainingTheme.centerControl:
        return 'Center control';
      case TrainingTheme.pieceDevelopment:
        return 'Piece development';
      case TrainingTheme.materialAwareness:
        return 'Material awareness';
      case TrainingTheme.pawnStructure:
        return 'Pawn structure';
      case TrainingTheme.prophylaxis:
        return 'Prophylactic thinking';
      case TrainingTheme.tempo:
        return 'Tempo and initiative';
      case TrainingTheme.initiative:
        return 'Initiative and attack';
      case TrainingTheme.coordination:
        return 'Piece coordination';
    }
  }

  String get description {
    switch (this) {
      case TrainingTheme.tactics:
        return 'Look for captures, checks, and threats before each move. Train pattern recognition with tactics puzzles.';
      case TrainingTheme.endgame:
        return 'Study basic endgame principles: activate the king, push passed pawns, and trade down when ahead.';
      case TrainingTheme.opening:
        return 'Develop pieces, control the center, and castle early. Avoid moving the same piece twice in the opening.';
      case TrainingTheme.kingSafety:
        return 'Castle early, keep pawns around the king, and be careful about opening lines near your king.';
      case TrainingTheme.centerControl:
        return 'Control the central squares e4, d4, e5, d5 with pawns and pieces. A strong center gives space and attacking chances.';
      case TrainingTheme.pieceDevelopment:
        return 'Bring all minor pieces into play before starting an attack. Develop knights before bishops.';
      case TrainingTheme.materialAwareness:
        return 'Count attackers and defenders before trading. Be careful of hanging pieces and double attacks.';
      case TrainingTheme.pawnStructure:
        return 'Avoid doubled, isolated, or backward pawns unless you have compensation. Pawns cannot move backward.';
      case TrainingTheme.prophylaxis:
        return 'Anticipate your opponent\'s ideas and prevent them before executing your own plans.';
      case TrainingTheme.tempo:
        return 'Gain time by making moves that attack multiple targets or force your opponent to respond.';
      case TrainingTheme.initiative:
        return 'Keep the pressure on. Active piece play is often worth a pawn. Look for forcing moves.';
      case TrainingTheme.coordination:
        return 'Make sure your pieces work together. A well-coordinated army beats a collection of strong but scattered pieces.';
    }
  }
}
