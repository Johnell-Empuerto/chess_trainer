class ImportedGame {
  final Map<String, String> headers;
  final List<String> sanMoves;
  final String? result;
  final String? startingFen;
  final String? event;
  final String? white;
  final String? black;
  final String? date;
  final String? opening;
  final String? variant;

  const ImportedGame({
    required this.headers,
    required this.sanMoves,
    this.result,
    this.startingFen,
    this.event,
    this.white,
    this.black,
    this.date,
    this.opening,
    this.variant,
  });
}
