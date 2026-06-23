import 'dart:convert';
import 'dart:io';

const _sourceDirectory = 'assets/openings/source';
const _outputPath = 'assets/openings/eco_openings.json';
const _sourceFileNames = ['a.tsv', 'b.tsv', 'c.tsv', 'd.tsv', 'e.tsv'];

Future<void> main(List<String> args) async {
  final openings = <_OpeningRecord>[];
  final seen = <String>{};

  for (final fileName in _sourceFileNames) {
    final file = File('$_sourceDirectory/$fileName');
    if (!await file.exists()) {
      stderr.writeln('Opening source file not found: ${file.path}');
      exitCode = 1;
      return;
    }

    final parsed = await _readSourceFile(file);
    for (final opening in parsed) {
      final key = '${opening.eco}\u0001${opening.name}\u0001'
          '${opening.moves.join('\u0001')}';
      if (seen.add(key)) {
        openings.add(opening);
      }
    }
  }

  openings.sort((a, b) {
    final ecoCompare = a.eco.compareTo(b.eco);
    if (ecoCompare != 0) return ecoCompare;

    final depthCompare = a.moves.length.compareTo(b.moves.length);
    if (depthCompare != 0) return depthCompare;

    return a.name.compareTo(b.name);
  });

  final output = File(_outputPath);
  await output.parent.create(recursive: true);

  const encoder = JsonEncoder.withIndent('  ');
  await output.writeAsString(
    '${encoder.convert(openings.map((opening) => opening.toJson()).toList())}\n',
  );

  stdout.writeln('Generated ${openings.length} openings at $_outputPath');
}

Future<List<_OpeningRecord>> _readSourceFile(File file) async {
  final lines = await file.readAsLines(encoding: utf8);
  if (lines.isEmpty) return const [];

  final records = <_OpeningRecord>[];
  final headerColumns = _splitTsvLine(lines.first);
  final header = _headerIndexes(headerColumns);
  final hasHeader = header != null;
  final startIndex = hasHeader ? 1 : 0;

  for (var i = startIndex; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;

    final columns = _splitTsvLine(line);
    final parsed = hasHeader
        ? _recordFromHeader(columns, header)
        : _recordWithoutHeader(columns);

    if (parsed == null || parsed.moves.isEmpty) {
      continue;
    }

    records.add(parsed);
  }

  return records;
}

Map<String, int>? _headerIndexes(List<String> columns) {
  final normalized = <String, int>{};

  for (var i = 0; i < columns.length; i++) {
    normalized[columns[i].trim().toLowerCase()] = i;
  }

  if (!normalized.containsKey('eco') ||
      !normalized.containsKey('name') ||
      !normalized.containsKey('pgn')) {
    return null;
  }

  return normalized;
}

_OpeningRecord? _recordFromHeader(
  List<String> columns,
  Map<String, int> header,
) {
  final eco = _valueAt(columns, header['eco']!);
  final name = _valueAt(columns, header['name']!);
  final pgn = _valueAt(columns, header['pgn']!);

  if (!_isEco(eco) || name.isEmpty || pgn.isEmpty) {
    return null;
  }

  return _OpeningRecord(
    eco: eco,
    name: name,
    moves: _movesFromPgn(pgn),
  );
}

_OpeningRecord? _recordWithoutHeader(List<String> columns) {
  if (columns.length < 3) return null;

  final ecoIndex = columns.indexWhere(_isEco);
  if (ecoIndex == -1) return null;

  final pgnIndex = columns.indexWhere(_looksLikePgn);
  if (pgnIndex == -1 || pgnIndex == ecoIndex) return null;

  final nameIndex = columns.indexWhere(
    (value) =>
        value.trim().isNotEmpty &&
        value != columns[ecoIndex] &&
        value != columns[pgnIndex],
  );
  if (nameIndex == -1) return null;

  return _OpeningRecord(
    eco: columns[ecoIndex].trim(),
    name: columns[nameIndex].trim(),
    moves: _movesFromPgn(columns[pgnIndex]),
  );
}

List<String> _splitTsvLine(String line) {
  return line.split('\t');
}

String _valueAt(List<String> columns, int index) {
  if (index < 0 || index >= columns.length) return '';
  return columns[index].trim();
}

bool _isEco(String value) {
  return RegExp(r'^[A-E]\d{2}$').hasMatch(value.trim());
}

bool _looksLikePgn(String value) {
  final trimmed = value.trim();
  return RegExp(r'^\d+\.').hasMatch(trimmed) ||
      RegExp(r'^[PNBRQKOa-h]').hasMatch(trimmed);
}

List<String> _movesFromPgn(String pgn) {
  var text = pgn
      .replaceAll(RegExp(r'\{[^}]*\}', dotAll: true), ' ')
      .replaceAll(RegExp(r';[^\n\r]*'), ' ')
      .replaceAll(RegExp(r'<[^>]*>', dotAll: true), ' ')
      .replaceAll(RegExp(r'\$\d+'), ' ')
      .replaceAll(RegExp(r'\d+\.{1,3}'), ' ');

  var previous = '';
  while (previous != text) {
    previous = text;
    text = text.replaceAll(RegExp(r'\([^()]*\)', dotAll: true), ' ');
  }

  return text
      .split(RegExp(r'\s+'))
      .map(_normalizeMoveToken)
      .where((token) => token.isNotEmpty && !_isResultToken(token))
      .toList(growable: false);
}

String _normalizeMoveToken(String token) {
  return token
      .trim()
      .replaceAll('0-0-0', 'O-O-O')
      .replaceAll('0-0', 'O-O')
      .replaceAll(RegExp(r'[+#?!]+$'), '')
      .replaceAll(RegExp(r'e\.p\.$'), '');
}

bool _isResultToken(String token) {
  return token == '1-0' || token == '0-1' || token == '1/2-1/2' || token == '*';
}

class _OpeningRecord {
  final String eco;
  final String name;
  final List<String> moves;

  const _OpeningRecord({
    required this.eco,
    required this.name,
    required this.moves,
  });

  Map<String, Object?> toJson() {
    return {
      'eco': eco,
      'name': name,
      'moves': moves,
    };
  }
}
