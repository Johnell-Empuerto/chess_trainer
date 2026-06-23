import 'package:chess_trainer/features/import_game/domain/imported_game.dart';

class PgnImportException implements Exception {
  final String message;

  const PgnImportException(this.message);

  @override
  String toString() => message;
}

class PgnImportService {
  ImportedGame parse(String pgnText) {
    final originalText = pgnText.trim();
    if (originalText.isEmpty) {
      throw const PgnImportException('Paste PGN text or choose a PGN file.');
    }

    final normalizedText = originalText.replaceAll('\r\n', '\n');
    final headers = _parseHeaders(normalizedText);
    final result =
        _headerValue(headers, 'Result') ?? _resultFromBody(normalizedText);
    final movetext = _cleanMovetext(_removeHeaderLines(normalizedText));
    final sanMoves = _parseSanMoves(movetext);

    if (sanMoves.isEmpty) {
      throw const PgnImportException('No legal moves were found in this PGN.');
    }

    return ImportedGame(
      headers: headers,
      sanMoves: sanMoves,
      result: result,
      startingFen: _headerValue(headers, 'FEN'),
      event: _headerValue(headers, 'Event'),
      white: _headerValue(headers, 'White'),
      black: _headerValue(headers, 'Black'),
      date: _headerValue(headers, 'Date'),
      opening: _headerValue(headers, 'Opening') ??
          _headerValue(headers, 'ECOUrl') ??
          _headerValue(headers, 'ECO'),
      variant: _headerValue(headers, 'Variant'),
    );
  }

  Map<String, String> _parseHeaders(String pgnText) {
    final headers = <String, String>{};
    final headerPattern = RegExp(
      r'^\s*\[([A-Za-z0-9_]+)\s+"((?:\\.|[^"\\])*)"\]\s*$',
      multiLine: true,
    );

    for (final match in headerPattern.allMatches(pgnText)) {
      final key = match.group(1);
      final value = match.group(2);
      if (key == null || value == null) continue;
      headers[key] = _unescapeHeaderValue(value);
    }

    return headers;
  }

  String _unescapeHeaderValue(String value) {
    return value.replaceAll(r'\"', '"').replaceAll(r'\\', '\\');
  }

  String? _headerValue(Map<String, String> headers, String key) {
    final value = headers[key]?.trim();
    return value == null || value.isEmpty || value == '?' ? null : value;
  }

  String _removeHeaderLines(String pgnText) {
    return pgnText
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('['))
        .join('\n');
  }

  String? _resultFromBody(String pgnText) {
    final match =
        RegExp(r'(^|\s)(1-0|0-1|1/2-1/2|\*)(?=\s|$)').firstMatch(pgnText);
    return match?.group(2);
  }

  String _cleanMovetext(String text) {
    var cleaned = _removeBraceComments(text);
    cleaned = _removeSemicolonComments(cleaned);
    cleaned = _removeVariations(cleaned);
    cleaned = cleaned.replaceAll(RegExp(r'\[%[^\]]*\]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\$\d+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'<[^>]*>'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.trim();
  }

  String _removeBraceComments(String text) {
    final buffer = StringBuffer();
    var depth = 0;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '{') {
        depth++;
        continue;
      }
      if (char == '}') {
        if (depth > 0) depth--;
        continue;
      }
      if (depth == 0) buffer.write(char);
    }

    return buffer.toString();
  }

  String _removeSemicolonComments(String text) {
    return text.split('\n').map((line) {
      final index = line.indexOf(';');
      return index < 0 ? line : line.substring(0, index);
    }).join('\n');
  }

  String _removeVariations(String text) {
    final buffer = StringBuffer();
    var depth = 0;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '(') {
        depth++;
        continue;
      }
      if (char == ')') {
        if (depth > 0) depth--;
        continue;
      }
      if (depth == 0) buffer.write(char);
    }

    return buffer.toString();
  }

  List<String> _parseSanMoves(String movetext) {
    var cleaned = movetext;
    cleaned = cleaned.replaceAll(RegExp(r'\b\d+\s*\.(?:\s*\.\.)?'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\.\.\.\s*'), ' ');
    cleaned = cleaned.replaceAll(
      RegExp(r'(^|\s)(1-0|0-1|1/2-1/2|\*)(?=\s|$)'),
      ' ',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (cleaned.isEmpty) return const [];

    final moves = <String>[];
    for (final rawToken in cleaned.split(' ')) {
      final move = _cleanSanToken(rawToken);
      if (move == null) continue;
      moves.add(move);
    }

    return moves;
  }

  String? _cleanSanToken(String token) {
    var cleaned = token.trim();
    if (cleaned.isEmpty) return null;
    if (RegExp(r'^\d+\.{1,3}$').hasMatch(cleaned)) return null;
    if (RegExp(r'^(1-0|0-1|1/2-1/2|\*)$').hasMatch(cleaned)) return null;
    if (RegExp(r'^\$\d+$').hasMatch(cleaned)) return null;
    if (RegExp(r'^[!?]+$').hasMatch(cleaned)) return null;

    cleaned = cleaned.replaceAll(RegExp(r'^[\s.]+|[\s,;]+$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[!?]+$'), '');
    cleaned = cleaned.replaceAll('0-0-0', 'O-O-O');
    cleaned = cleaned.replaceAll('0-0', 'O-O');

    if (cleaned.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(cleaned)) return null;
    if (cleaned.startsWith('[') || cleaned.endsWith(']')) return null;

    return cleaned;
  }
}
