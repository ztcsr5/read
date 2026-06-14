// Faithful Dart port of legado's QueryTTF.java (book-source font anti-crawl
// decoder). Ported item-by-item from the open-source implementation so that
// `java.queryTTF(...)` in JSON book sources behaves the same as in legado /
// "\u6e90\u9605\u8bfb". TrueType/OpenType is big-endian.
//
// Reference: io/legado/app/model/analyzeRule/QueryTTF.java
//
// Usage from the JS bridge:
//   final ttf = QueryTTF(fontBytes);
//   ttf.getGlyfByUnicode(0xE000);   // outline string for a code point
//   ttf.getUnicodeByGlyf(outline);  // reverse: real unicode for an outline
//   ttf.getGlyfIdByUnicode(0xE000); // glyph index
//
// This file is self-contained (only dart:typed_data) and has no dependency on
// the rest of the app, so it can be unit-tested in isolation.

import 'dart:typed_data';

/// Big-endian binary reader mirroring QueryTTF.BufferReader.
class _BufferReader {
  final ByteData _bd;
  final Uint8List _bytes;
  int _pos;

  _BufferReader(Uint8List buffer, int index)
    : _bd = ByteData.sublistView(buffer),
      _bytes = buffer,
      _pos = index;

  int get position => _pos;
  set position(int index) => _pos = index;

  int readUint64() {
    final v = _bd.getUint64(_pos, Endian.big);
    _pos += 8;
    return v;
  }

  int readUint32() {
    final v = _bd.getUint32(_pos, Endian.big);
    _pos += 4;
    return v;
  }

  int readInt32() {
    final v = _bd.getInt32(_pos, Endian.big);
    _pos += 4;
    return v;
  }

  int readUint16() {
    final v = _bd.getUint16(_pos, Endian.big);
    _pos += 2;
    return v;
  }

  int readInt16() {
    final v = _bd.getInt16(_pos, Endian.big);
    _pos += 2;
    return v;
  }

  int readUint8() {
    final v = _bytes[_pos];
    _pos += 1;
    return v;
  }

  int readInt8() {
    final v = _bd.getInt8(_pos);
    _pos += 1;
    return v;
  }

  Uint8List readByteArray(int len) {
    final result = Uint8List.fromList(_bytes.sublist(_pos, _pos + len));
    _pos += len;
    return result;
  }

  List<int> readUint8Array(int len) {
    final result = List<int>.filled(len, 0);
    for (var i = 0; i < len; ++i) {
      result[i] = readUint8();
    }
    return result;
  }

  List<int> readInt16Array(int len) {
    final result = List<int>.filled(len, 0);
    for (var i = 0; i < len; ++i) {
      result[i] = readInt16();
    }
    return result;
  }

  List<int> readUint16Array(int len) {
    final result = List<int>.filled(len, 0);
    for (var i = 0; i < len; ++i) {
      result[i] = readUint16();
    }
    return result;
  }

  List<int> readInt32Array(int len) {
    final result = List<int>.filled(len, 0);
    for (var i = 0; i < len; ++i) {
      result[i] = readInt32();
    }
    return result;
  }
}

class _Directory {
  String tableTag = '';
  int checkSum = 0;
  int offset = 0;
  int length = 0;
}

class _HeadLayout {
  int unitsPerEm = 0;
  int indexToLocFormat = 0;
}

class _MaxpLayout {
  int numGlyphs = 0;
  int maxContours = 0;
}

class _GlyphSimple {
  List<int> endPtsOfContours = const [];
  int instructionLength = 0;
  List<int> instructions = const [];
  List<int> flags = const [];
  List<int> xCoordinates = const [];
  List<int> yCoordinates = const [];
}

class _GlyphComponent {
  int flags = 0;
  int glyphIndex = 0;
  int argument1 = 0;
  int argument2 = 0;
  double xScale = 0;
  double scale01 = 0;
  double scale10 = 0;
  double yScale = 0;
}

class _GlyfLayout {
  int numberOfContours = 0;
  int xMin = 0;
  int yMin = 0;
  int xMax = 0;
  int yMax = 0;
  _GlyphSimple? glyphSimple;
  List<_GlyphComponent>? glyphComponent;
}

/// Parses a TTF/OTF font and exposes unicode<->glyph-outline lookups, used to
/// reverse anti-crawl font obfuscation in novel book sources.
class QueryTTF {
  final Map<String, _Directory> _directorys = {};
  final _HeadLayout _head = _HeadLayout();
  final _MaxpLayout _maxp = _MaxpLayout();

  // cmap platform/encoding preference order (kept for reference parity).
  // ignore: unused_field
  static const List<List<int>> _pps = [
    [3, 10],
    [0, 4],
    [3, 1],
    [1, 0],
    [0, 3],
    [0, 1],
  ];

  List<int> _loca = const [];
  late List<_GlyfLayout?> _glyfArray;

  final Map<int, String> unicodeToGlyph = {};
  final Map<String, int> glyphToUnicode = {};
  final Map<int, int> unicodeToGlyphId = {};

  QueryTTF(Uint8List buffer) {
    final fontReader = _BufferReader(buffer, 0);
    // File header.
    fontReader.readUint32(); // sfntVersion
    final numTables = fontReader.readUint16();
    fontReader.readUint16(); // searchRange
    fontReader.readUint16(); // entrySelector
    fontReader.readUint16(); // rangeShift

    // Table directory.
    for (var i = 0; i < numTables; ++i) {
      final d = _Directory();
      d.tableTag = String.fromCharCodes(fontReader.readByteArray(4));
      d.checkSum = fontReader.readUint32();
      d.offset = fontReader.readUint32();
      d.length = fontReader.readUint32();
      _directorys[d.tableTag] = d;
    }

    _readHeadTable(buffer);
    _readCmapTable(buffer);
    _readLocaTable(buffer);
    _readMaxpTable(buffer);
    _readGlyfTable(buffer);

    // Build unicode <-> glyph maps.
    final glyfArrayLength = _glyfArray.length;
    unicodeToGlyphId.forEach((key, val) {
      if (val >= glyfArrayLength) return;
      final glyfString = _getGlyfById(val);
      unicodeToGlyph[key] = glyfString ?? '';
      if (glyfString == null) return;
      glyphToUnicode[glyfString] = key;
    });
  }

  void _readHeadTable(Uint8List buffer) {
    final dataTable = _directorys['head'];
    if (dataTable == null) return;
    final reader = _BufferReader(buffer, dataTable.offset);
    reader.readUint16(); // majorVersion
    reader.readUint16(); // minorVersion
    reader.readUint32(); // fontRevision
    reader.readUint32(); // checkSumAdjustment
    reader.readUint32(); // magicNumber
    reader.readUint16(); // flags
    _head.unitsPerEm = reader.readUint16();
    reader.readUint64(); // created
    reader.readUint64(); // modified
    reader.readInt16(); // xMin
    reader.readInt16(); // yMin
    reader.readInt16(); // xMax
    reader.readInt16(); // yMax
    reader.readUint16(); // macStyle
    reader.readUint16(); // lowestRecPPEM
    reader.readInt16(); // fontDirectionHint
    _head.indexToLocFormat = reader.readInt16();
    reader.readInt16(); // glyphDataFormat
  }

  void _readCmapTable(Uint8List buffer) {
    final dataTable = _directorys['cmap'];
    if (dataTable == null) return;
    final reader = _BufferReader(buffer, dataTable.offset);
    reader.readUint16(); // version
    final numTables = reader.readUint16();
    final records = <List<int>>[]; // [platformID, encodingID, offset]
    for (var i = 0; i < numTables; ++i) {
      final platformID = reader.readUint16();
      final encodingID = reader.readUint16();
      final offset = reader.readUint32();
      records.add([platformID, encodingID, offset]);
    }

    final seenOffsets = <int>{};
    for (final rec in records) {
      final fmtOffset = rec[2];
      if (seenOffsets.contains(fmtOffset)) continue;
      seenOffsets.add(fmtOffset);
      reader.position = dataTable.offset + fmtOffset;

      final format = reader.readUint16();
      final length = reader.readUint16();
      reader.readUint16(); // language
      switch (format) {
        case 0:
          {
            final glyphIdArray = reader.readUint8Array(length - 6);
            for (var unicode = 0; unicode < glyphIdArray.length; unicode++) {
              if (glyphIdArray[unicode] == 0) continue;
              unicodeToGlyphId[unicode] = glyphIdArray[unicode];
            }
            break;
          }
        case 4:
          {
            final segCountX2 = reader.readUint16();
            final segCount = segCountX2 ~/ 2;
            reader.readUint16(); // searchRange
            reader.readUint16(); // entrySelector
            reader.readUint16(); // rangeShift
            final endCode = reader.readUint16Array(segCount);
            reader.readUint16(); // reservedPad
            final startCode = reader.readUint16Array(segCount);
            final idDelta = reader.readInt16Array(segCount);
            final idRangeOffsets = reader.readUint16Array(segCount);
            final glyphIdArrayLength = (length - 16 - (segCount * 8)) ~/ 2;
            final glyphIdArray = glyphIdArrayLength > 0
                ? reader.readUint16Array(glyphIdArrayLength)
                : const <int>[];

            for (var s = 0; s < segCount; s++) {
              final unicodeInclusive = startCode[s];
              final unicodeExclusive = endCode[s];
              final delta = idDelta[s];
              final idRangeOffset = idRangeOffsets[s];
              for (
                var unicode = unicodeInclusive;
                unicode <= unicodeExclusive;
                unicode++
              ) {
                if (unicode == 0xFFFF) continue;
                int glyphId = 0;
                if (idRangeOffset == 0) {
                  glyphId = (unicode + delta) & 0xFFFF;
                } else {
                  final gIndex =
                      (idRangeOffset ~/ 2) +
                      unicode -
                      unicodeInclusive +
                      s -
                      segCount;
                  if (gIndex >= 0 && gIndex < glyphIdArray.length) {
                    glyphId = (glyphIdArray[gIndex] + delta) & 0xFFFF;
                  }
                }
                if (glyphId == 0) continue;
                unicodeToGlyphId[unicode] = glyphId;
              }
            }
            break;
          }
        case 6:
          {
            final firstCode = reader.readUint16();
            final entryCount = reader.readUint16();
            final glyphIdArray = reader.readUint16Array(entryCount);
            var unicodeIndex = firstCode;
            for (var gIndex = 0; gIndex < entryCount; gIndex++) {
              unicodeToGlyphId[unicodeIndex] = glyphIdArray[gIndex];
              unicodeIndex++;
            }
            break;
          }
        default:
          break;
      }
    }
  }

  void _readLocaTable(Uint8List buffer) {
    final dataTable = _directorys['loca'];
    if (dataTable == null) return;
    final reader = _BufferReader(buffer, dataTable.offset);
    if (_head.indexToLocFormat == 0) {
      _loca = reader.readUint16Array(dataTable.length ~/ 2);
      for (var i = 0; i < _loca.length; i++) {
        _loca[i] *= 2;
      }
    } else {
      _loca = reader.readInt32Array(dataTable.length ~/ 4);
    }
  }

  void _readMaxpTable(Uint8List buffer) {
    final dataTable = _directorys['maxp'];
    if (dataTable == null) return;
    final reader = _BufferReader(buffer, dataTable.offset);
    reader.readUint32(); // version
    _maxp.numGlyphs = reader.readUint16();
    reader.readUint16(); // maxPoints
    _maxp.maxContours = reader.readUint16();
    // remaining maxp fields are unused for decoding
  }

  void _readGlyfTable(Uint8List buffer) {
    final dataTable = _directorys['glyf'];
    if (dataTable == null) {
      _glyfArray = List<_GlyfLayout?>.filled(_maxp.numGlyphs, null);
      return;
    }
    final glyfCount = _maxp.numGlyphs;
    _glyfArray = List<_GlyfLayout?>.filled(glyfCount, null);
    final reader = _BufferReader(buffer, 0);
    for (var index = 0; index < glyfCount; index++) {
      if (index + 1 >= _loca.length) break;
      if (_loca[index] == _loca[index + 1]) continue;
      final offset = dataTable.offset + _loca[index];
      final glyph = _GlyfLayout();
      reader.position = offset;
      glyph.numberOfContours = reader.readInt16();
      if (glyph.numberOfContours > _maxp.maxContours) continue;
      glyph.xMin = reader.readInt16();
      glyph.yMin = reader.readInt16();
      glyph.xMax = reader.readInt16();
      glyph.yMax = reader.readInt16();
      if (glyph.numberOfContours == 0) continue;
      if (glyph.numberOfContours > 0) {
        // Simple glyph.
        final simple = _GlyphSimple();
        simple.endPtsOfContours = reader.readUint16Array(
          glyph.numberOfContours,
        );
        simple.instructionLength = reader.readUint16();
        simple.instructions = reader.readUint8Array(simple.instructionLength);
        final flagLength =
            simple.endPtsOfContours[simple.endPtsOfContours.length - 1] + 1;
        final flags = List<int>.filled(flagLength, 0);
        for (var n = 0; n < flagLength; ++n) {
          final glyphSimpleFlag = reader.readUint8();
          flags[n] = glyphSimpleFlag;
          if ((glyphSimpleFlag & 0x08) == 0x08) {
            for (var m = reader.readUint8(); m > 0 && n + 1 < flagLength; --m) {
              flags[++n] = glyphSimpleFlag;
            }
          }
        }
        simple.flags = flags;
        final xCoordinates = List<int>.filled(flagLength, 0);
        for (var n = 0; n < flagLength; ++n) {
          switch (flags[n] & 0x12) {
            case 0x02:
              xCoordinates[n] = -1 * reader.readUint8();
              break;
            case 0x12:
              xCoordinates[n] = reader.readUint8();
              break;
            case 0x10:
              xCoordinates[n] = 0;
              break;
            case 0x00:
              xCoordinates[n] = reader.readInt16();
              break;
          }
        }
        simple.xCoordinates = xCoordinates;
        final yCoordinates = List<int>.filled(flagLength, 0);
        for (var n = 0; n < flagLength; ++n) {
          switch (flags[n] & 0x24) {
            case 0x04:
              yCoordinates[n] = -1 * reader.readUint8();
              break;
            case 0x24:
              yCoordinates[n] = reader.readUint8();
              break;
            case 0x20:
              yCoordinates[n] = 0;
              break;
            case 0x00:
              yCoordinates[n] = reader.readInt16();
              break;
          }
        }
        simple.yCoordinates = yCoordinates;
        glyph.glyphSimple = simple;
      } else {
        // Composite glyph.
        final components = <_GlyphComponent>[];
        while (true) {
          final c = _GlyphComponent();
          c.flags = reader.readUint16();
          c.glyphIndex = reader.readUint16();
          switch (c.flags & 0x03) {
            case 0x00:
              c.argument1 = reader.readUint8();
              c.argument2 = reader.readUint8();
              break;
            case 0x02:
              c.argument1 = reader.readInt8();
              c.argument2 = reader.readInt8();
              break;
            case 0x01:
              c.argument1 = reader.readUint16();
              c.argument2 = reader.readUint16();
              break;
            case 0x03:
              c.argument1 = reader.readInt16();
              c.argument2 = reader.readInt16();
              break;
          }
          switch (c.flags & 0xC8) {
            case 0x08:
              c.yScale = c.xScale = reader.readUint16() / 16384.0;
              break;
            case 0x40:
              c.xScale = reader.readUint16() / 16384.0;
              c.yScale = reader.readUint16() / 16384.0;
              break;
            case 0x80:
              c.xScale = reader.readUint16() / 16384.0;
              c.scale01 = reader.readUint16() / 16384.0;
              c.scale10 = reader.readUint16() / 16384.0;
              c.yScale = reader.readUint16() / 16384.0;
              break;
          }
          components.add(c);
          if ((c.flags & 0x20) == 0) break;
        }
        glyph.glyphComponent = components;
      }
      _glyfArray[index] = glyph;
    }
  }

  String? _getGlyfById(int glyfId) {
    if (glyfId < 0 || glyfId >= _glyfArray.length) return null;
    final glyph = _glyfArray[glyfId];
    if (glyph == null) return null;
    if (glyph.numberOfContours >= 0) {
      final simple = glyph.glyphSimple;
      if (simple == null) return null;
      final dataCount = simple.flags.length;
      final coordinateArray = List<String>.filled(dataCount, '');
      for (var i = 0; i < dataCount; i++) {
        coordinateArray[i] =
            '${simple.xCoordinates[i]},${simple.yCoordinates[i]}';
      }
      return coordinateArray.join('|');
    } else {
      final list = <String>[];
      for (final g in glyph.glyphComponent ?? const <_GlyphComponent>[]) {
        list.add(
          '{flags:${g.flags},glyphIndex:${g.glyphIndex},'
          'arg1:${g.argument1},arg2:${g.argument2},'
          'xScale:${g.xScale},scale01:${g.scale01},'
          'scale10:${g.scale10},yScale:${g.yScale}}',
        );
      }
      return '[${list.join(',')}]';
    }
  }

  /// Glyph index for a unicode value (0 when not found).
  int getGlyfIdByUnicode(int unicode) => unicodeToGlyphId[unicode] ?? 0;

  /// Outline string for a unicode value.
  String? getGlyfByUnicode(int unicode) => unicodeToGlyph[unicode];

  /// Reverse lookup: unicode for an outline string (0 when not found).
  int getUnicodeByGlyf(String glyph) => glyphToUnicode[glyph] ?? 0;

  /// Whether a unicode value is a blank/whitespace character.
  bool isBlankUnicode(int unicode) {
    switch (unicode) {
      case 0x0009:
      case 0x0020:
      case 0x00A0:
      case 0x2002:
      case 0x2003:
      case 0x2007:
      case 0x200A:
      case 0x200B:
      case 0x200C:
      case 0x200D:
      case 0x202F:
      case 0x205F:
        return true;
      default:
        return false;
    }
  }
}
