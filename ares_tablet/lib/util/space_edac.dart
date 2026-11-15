import 'dart:convert';

String crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
    }
  }
  return ((crc ^ 0xffffffff) & 0xffffffff)
      .toRadixString(16)
      .padLeft(8, '0')
      .toUpperCase();
}

List<int> encodeHamming74(List<int> bytes) {
  int encode(int n) {
    final d1 = (n >> 3) & 1, d2 = (n >> 2) & 1, d3 = (n >> 1) & 1, d4 = n & 1;
    return ((d1 ^ d2 ^ d4) << 6) |
        ((d1 ^ d3 ^ d4) << 5) |
        (d1 << 4) |
        ((d2 ^ d3 ^ d4) << 3) |
        (d2 << 2) |
        (d3 << 1) |
        d4;
  }

  return bytes.expand((b) => [encode(b >> 4), encode(b & 15)]).toList();
}

(List<int>, int) decodeHamming74(List<int> words) {
  if (words.length.isOdd) {
    throw ArgumentError('Expected two codewords per byte');
  }
  var corrected = 0;
  int decode(int word) {
    final b = List.generate(7, (i) => (word >> (6 - i)) & 1);
    final syndrome =
        (b[0] ^ b[2] ^ b[4] ^ b[6]) |
        ((b[1] ^ b[2] ^ b[5] ^ b[6]) << 1) |
        ((b[3] ^ b[4] ^ b[5] ^ b[6]) << 2);
    if (syndrome != 0) {
      b[syndrome - 1] ^= 1;
      corrected++;
    }
    return (b[2] << 3) | (b[4] << 2) | (b[5] << 1) | b[6];
  }

  final bytes = <int>[];
  for (var i = 0; i < words.length; i += 2) {
    bytes.add((decode(words[i]) << 4) | decode(words[i + 1]));
  }
  return (bytes, corrected);
}

class EdacResult {
  EdacResult(
    this.sent,
    this.received,
    this.txCrc,
    this.rxCrc,
    this.correctedWords,
    this.flips,
  );
  final String sent, received, txCrc, rxCrc;
  final int correctedWords, flips;
  bool get verified => txCrc == rxCrc;
}

EdacResult testSpaceLink(
  String message, {
  int flips = 1,
  bool doubleError = false,
}) {
  if (flips < 0) throw ArgumentError.value(flips, 'flips');
  final bytes = utf8.encode(message),
      words = encodeHamming74(utf8.encode(message));
  var actual = 0;
  for (var i = 0; i < flips && i < words.length; i++) {
    words[i] ^= 1 << (i % 7);
    actual++;
    if (doubleError) {
      words[i] ^= 1 << ((i + 1) % 7);
      actual++;
    }
  }
  final decoded = decodeHamming74(words);
  return EdacResult(
    message,
    utf8.decode(decoded.$1, allowMalformed: true),
    crc32(bytes),
    crc32(decoded.$1),
    decoded.$2,
    actual,
  );
}
