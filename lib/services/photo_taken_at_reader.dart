import 'dart:io';
import 'dart:typed_data';

class PhotoTakenAtReader {
  Future<DateTime?> readTakenAt(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    return _readJpegExifDateTime(bytes);
  }

  DateTime? _readJpegExifDateTime(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return null;
    }

    var offset = 2;
    while (offset + 4 < bytes.length) {
      if (bytes[offset] != 0xFF) return null;
      final marker = bytes[offset + 1];
      offset += 2;

      if (marker == 0xDA || marker == 0xD9) break;
      if (offset + 2 > bytes.length) return null;

      final segmentLength = _readUint16(bytes, offset, false);
      if (segmentLength < 2 || offset + segmentLength > bytes.length) {
        return null;
      }

      final segmentStart = offset + 2;
      final segmentEnd = offset + segmentLength;
      if (marker == 0xE1) {
        final dateTime = _readExifSegment(bytes, segmentStart, segmentEnd);
        if (dateTime != null) return dateTime;
      }

      offset += segmentLength;
    }

    return null;
  }

  DateTime? _readExifSegment(Uint8List bytes, int start, int end) {
    const exifHeader = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00];
    if (end - start < exifHeader.length + 8) return null;
    for (var i = 0; i < exifHeader.length; i++) {
      if (bytes[start + i] != exifHeader[i]) return null;
    }

    final tiffStart = start + exifHeader.length;
    final littleEndian =
        bytes[tiffStart] == 0x49 && bytes[tiffStart + 1] == 0x49;
    final bigEndian = bytes[tiffStart] == 0x4D && bytes[tiffStart + 1] == 0x4D;
    if (!littleEndian && !bigEndian) return null;
    if (_readUint16(bytes, tiffStart + 2, littleEndian) != 42) return null;

    final firstIfdOffset = _readUint32(bytes, tiffStart + 4, littleEndian);
    final firstIfd = tiffStart + firstIfdOffset;
    final exifIfdOffset = _findIfdValueOffset(
      bytes: bytes,
      ifdOffset: firstIfd,
      tag: 0x8769,
      littleEndian: littleEndian,
      tiffStart: tiffStart,
      segmentEnd: end,
    );

    final primaryDate = _readAsciiTag(
      bytes: bytes,
      ifdOffset: firstIfd,
      tag: 0x0132,
      littleEndian: littleEndian,
      tiffStart: tiffStart,
      segmentEnd: end,
    );
    final originalDate = exifIfdOffset == null
        ? null
        : _readAsciiTag(
            bytes: bytes,
            ifdOffset: exifIfdOffset,
            tag: 0x9003,
            littleEndian: littleEndian,
            tiffStart: tiffStart,
            segmentEnd: end,
          );
    final digitizedDate = exifIfdOffset == null
        ? null
        : _readAsciiTag(
            bytes: bytes,
            ifdOffset: exifIfdOffset,
            tag: 0x9004,
            littleEndian: littleEndian,
            tiffStart: tiffStart,
            segmentEnd: end,
          );

    return _parseExifDateTime(originalDate ?? digitizedDate ?? primaryDate);
  }

  int? _findIfdValueOffset({
    required Uint8List bytes,
    required int ifdOffset,
    required int tag,
    required bool littleEndian,
    required int tiffStart,
    required int segmentEnd,
  }) {
    final entryOffset = _findIfdEntry(
      bytes: bytes,
      ifdOffset: ifdOffset,
      targetTag: tag,
      littleEndian: littleEndian,
      segmentEnd: segmentEnd,
    );
    if (entryOffset == null) return null;
    final value = _readUint32(bytes, entryOffset + 8, littleEndian);
    final absolute = tiffStart + value;
    if (absolute < tiffStart || absolute >= segmentEnd) return null;
    return absolute;
  }

  String? _readAsciiTag({
    required Uint8List bytes,
    required int ifdOffset,
    required int tag,
    required bool littleEndian,
    required int tiffStart,
    required int segmentEnd,
  }) {
    final entryOffset = _findIfdEntry(
      bytes: bytes,
      ifdOffset: ifdOffset,
      targetTag: tag,
      littleEndian: littleEndian,
      segmentEnd: segmentEnd,
    );
    if (entryOffset == null) return null;

    final type = _readUint16(bytes, entryOffset + 2, littleEndian);
    final count = _readUint32(bytes, entryOffset + 4, littleEndian);
    if (type != 2 || count <= 0) return null;

    final valueOffset = count <= 4
        ? entryOffset + 8
        : tiffStart + _readUint32(bytes, entryOffset + 8, littleEndian);
    if (valueOffset < 0 || valueOffset + count > segmentEnd) return null;

    final chars = bytes.sublist(valueOffset, valueOffset + count);
    return String.fromCharCodes(chars.where((byte) => byte != 0)).trim();
  }

  int? _findIfdEntry({
    required Uint8List bytes,
    required int ifdOffset,
    required int targetTag,
    required bool littleEndian,
    required int segmentEnd,
  }) {
    if (ifdOffset < 0 || ifdOffset + 2 > segmentEnd) return null;

    final count = _readUint16(bytes, ifdOffset, littleEndian);
    var entryOffset = ifdOffset + 2;
    for (var i = 0; i < count; i++) {
      if (entryOffset + 12 > segmentEnd) return null;
      final tag = _readUint16(bytes, entryOffset, littleEndian);
      if (tag == targetTag) return entryOffset;
      entryOffset += 12;
    }
    return null;
  }

  DateTime? _parseExifDateTime(String? value) {
    if (value == null || value.length < 19) return null;
    final match = RegExp(
      r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(value);
    if (match == null) return null;

    final parts = List.generate(
      6,
      (index) => int.tryParse(match.group(index + 1) ?? ''),
    );
    if (parts.any((part) => part == null)) return null;
    return DateTime(
      parts[0]!,
      parts[1]!,
      parts[2]!,
      parts[3]!,
      parts[4]!,
      parts[5]!,
    );
  }

  int _readUint16(Uint8List bytes, int offset, bool littleEndian) {
    final data = ByteData.sublistView(bytes, offset, offset + 2);
    return data.getUint16(0, littleEndian ? Endian.little : Endian.big);
  }

  int _readUint32(Uint8List bytes, int offset, bool littleEndian) {
    final data = ByteData.sublistView(bytes, offset, offset + 4);
    return data.getUint32(0, littleEndian ? Endian.little : Endian.big);
  }
}
