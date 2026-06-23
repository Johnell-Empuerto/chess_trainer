class OpeningName {
  final String eco;
  final String name;
  final List<String> moves;

  static const startingPosition = OpeningName(
    eco: '',
    name: 'Starting Position',
    moves: [],
  );

  const OpeningName({
    required this.eco,
    required this.name,
    required this.moves,
  });

  factory OpeningName.fromJson(Map<String, dynamic> json) {
    return OpeningName(
      eco: json['eco'] as String,
      name: json['name'] as String,
      moves: (json['moves'] as List<dynamic>).cast<String>(),
    );
  }

  bool get isStartingPosition =>
      eco.isEmpty && name == 'Starting Position' && moves.isEmpty;

  String get displayName => eco.isEmpty ? name : '$eco $name';
}
